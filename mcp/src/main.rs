//! MCP Server for Scalegraph Ledger
//!
//! Exposes ledger and business transaction operations via Model Context Protocol (MCP)
//! for integration with LLMs like Claude Desktop.
//!
//! Run: ./target/release/scalegraph-mcp
//!
//! Environment variables:
//!   SCALEGRAPH_GRPC_URL - gRPC server URL (default: http://localhost:50051)
//!   SCALEGRAPH_DEBUG - Enable debug output to stderr
//!
//! Tools exposed:
//! - list_participants: List all participants in the ecosystem
//! - get_participant_accounts: Get all accounts for a participant
//! - get_account_balance: Get balance for a specific account
//! - transfer: Execute atomic multi-party transfer
//! - purchase_invoice: Create B2B purchase invoice (receivables/payables)
//! - pay_invoice: Pay/settle a B2B invoice
//! - access_payment: Real-time micro-payment for access control
//!
//! Configure in Claude Desktop's settings as a stdio MCP server.

pub mod ledger {
    tonic::include_proto!("scalegraph.ledger");
}

use anyhow::Result;
use ledger::{
    business_service_client::BusinessServiceClient,
    ledger_service_client::LedgerServiceClient,
    participant_service_client::ParticipantServiceClient,
    AccessPaymentRequest, CreateParticipantAccountRequest, CreateParticipantRequest,
    GetBalanceRequest, GetParticipantAccountsRequest, ListParticipantsRequest,
    ListTransactionsRequest, PayInvoiceRequest, PurchaseInvoiceRequest, TransferEntry,
    TransferRequest,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};
use tonic::transport::Channel;

// ============================================================================
// MCP Protocol Types
// ============================================================================

#[derive(Debug, Deserialize)]
struct JsonRpcRequest {
    #[allow(dead_code)]
    jsonrpc: String,
    id: Option<Value>,
    method: String,
    params: Option<Value>,
}

#[derive(Debug, Serialize)]
struct JsonRpcResponse {
    jsonrpc: String,
    id: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<JsonRpcError>,
}

#[derive(Debug, Serialize)]
struct JsonRpcError {
    code: i32,
    message: String,
}

// ============================================================================
// gRPC Client
// ============================================================================

struct ScalegraphClient {
    ledger: LedgerServiceClient<Channel>,
    participant: ParticipantServiceClient<Channel>,
    business: BusinessServiceClient<Channel>,
}

impl ScalegraphClient {
    async fn connect(addr: &str) -> Result<Self> {
        let channel = Channel::from_shared(addr.to_string())?.connect().await?;

        Ok(Self {
            ledger: LedgerServiceClient::new(channel.clone()),
            participant: ParticipantServiceClient::new(channel.clone()),
            business: BusinessServiceClient::new(channel),
        })
    }

    async fn list_participants(&mut self) -> Result<Value> {
        let request = ListParticipantsRequest { role: 0 };
        let response = self.participant.list_participants(request).await?;
        let participants: Vec<Value> = response
            .into_inner()
            .participants
            .into_iter()
            .map(|p| {
                json!({
                    "id": p.id,
                    "name": p.name,
                    "role": role_to_string(p.role),
                })
            })
            .collect();
        Ok(json!({ "participants": participants }))
    }

    async fn create_participant(
        &mut self,
        id: &str,
        name: &str,
        role: i32,
    ) -> Result<Value> {
        let request = CreateParticipantRequest {
            id: id.to_string(),
            name: name.to_string(),
            role,
            metadata: std::collections::HashMap::new(),
        };
        let response = self.participant.create_participant(request).await?;
        let p = response.into_inner();
        Ok(json!({
            "id": p.id,
            "name": p.name,
            "role": role_to_string(p.role),
            "message": format!("Participant '{}' created successfully", p.name)
        }))
    }

    async fn create_participant_account(
        &mut self,
        participant_id: &str,
        account_type: i32,
        initial_balance: i64,
    ) -> Result<Value> {
        let request = CreateParticipantAccountRequest {
            participant_id: participant_id.to_string(),
            account_type,
            initial_balance,
            metadata: std::collections::HashMap::new(),
        };
        let response = self.participant.create_participant_account(request).await?;
        let a = response.into_inner();
        Ok(json!({
            "id": a.id,
            "participant_id": a.participant_id,
            "type": account_type_to_string(a.account_type),
            "balance": format_balance(a.balance),
            "balance_cents": a.balance,
            "message": format!("Account '{}' created successfully", a.id)
        }))
    }

    async fn get_participant_accounts(&mut self, participant_id: &str) -> Result<Value> {
        let request = GetParticipantAccountsRequest {
            participant_id: participant_id.to_string(),
        };
        let response = self.participant.get_participant_accounts(request).await?;
        let accounts: Vec<Value> = response
            .into_inner()
            .accounts
            .into_iter()
            .map(|a| {
                json!({
                    "id": a.id,
                    "type": account_type_to_string(a.account_type),
                    "balance": format_balance(a.balance),
                    "balance_cents": a.balance,
                })
            })
            .collect();
        Ok(json!({
            "participant_id": participant_id,
            "accounts": accounts
        }))
    }

    async fn get_balance(&mut self, account_id: &str) -> Result<Value> {
        let request = GetBalanceRequest {
            account_id: account_id.to_string(),
        };
        let response = self.ledger.get_balance(request).await?;
        let balance = response.into_inner().balance;
        Ok(json!({
            "account_id": account_id,
            "balance": format_balance(balance),
            "balance_cents": balance,
        }))
    }

    async fn transfer(&mut self, entries: Vec<(String, i64)>, reference: &str) -> Result<Value> {
        let request = TransferRequest {
            entries: entries
                .into_iter()
                .map(|(account_id, amount)| TransferEntry { account_id, amount })
                .collect(),
            reference: reference.to_string(),
        };
        let response = self.ledger.transfer(request).await?;
        let tx = response.into_inner();
        Ok(json!({
            "transaction_id": tx.id,
            "type": tx.r#type,
            "reference": tx.reference,
            "entries": tx.entries.iter().map(|e| json!({
                "account_id": e.account_id,
                "amount": format_balance(e.amount),
                "amount_cents": e.amount,
            })).collect::<Vec<_>>(),
        }))
    }

    async fn list_transactions(
        &mut self,
        limit: Option<i32>,
        account_id: Option<&str>,
    ) -> Result<Value> {
        let request = ListTransactionsRequest {
            limit: limit.unwrap_or(50),
            account_id: account_id.unwrap_or("").to_string(),
        };
        let response = self.ledger.list_transactions(request).await?;
        let transactions: Vec<Value> = response
            .into_inner()
            .transactions
            .into_iter()
            .map(|tx| {
                json!({
                    "transaction_id": tx.id,
                    "type": tx.r#type,
                    "reference": tx.reference,
                    "timestamp": tx.timestamp,
                    "entries": tx.entries.iter().map(|e| json!({
                        "account_id": e.account_id,
                        "amount": format_balance(e.amount),
                        "amount_cents": e.amount,
                    })).collect::<Vec<_>>(),
                })
            })
            .collect();
        Ok(json!({ "transactions": transactions }))
    }

    async fn purchase_invoice(
        &mut self,
        supplier_id: &str,
        buyer_id: &str,
        amount: i64,
        reference: &str,
    ) -> Result<Value> {
        let request = PurchaseInvoiceRequest {
            supplier_id: supplier_id.to_string(),
            buyer_id: buyer_id.to_string(),
            amount,
            reference: reference.to_string(),
        };
        let response = self.business.purchase_invoice(request).await?;
        let result = response.into_inner();
        Ok(json!({
            "transaction_id": result.transaction_id,
            "reference": result.reference,
            "amount": format_balance(result.amount),
            "amount_cents": result.amount,
            "status": result.status,
            "message": result.message,
        }))
    }

    async fn pay_invoice(
        &mut self,
        supplier_id: &str,
        buyer_id: &str,
        amount: i64,
        reference: &str,
    ) -> Result<Value> {
        let request = PayInvoiceRequest {
            supplier_id: supplier_id.to_string(),
            buyer_id: buyer_id.to_string(),
            amount,
            reference: reference.to_string(),
        };
        let response = self.business.pay_invoice(request).await?;
        let result = response.into_inner();
        Ok(json!({
            "transaction_id": result.transaction_id,
            "reference": result.reference,
            "amount": format_balance(result.amount),
            "amount_cents": result.amount,
            "status": result.status,
            "message": result.message,
        }))
    }

    async fn access_payment(
        &mut self,
        payer_id: &str,
        access_provider_id: &str,
        amount: i64,
        reference: &str,
        platform_id: Option<&str>,
        platform_fee: Option<i64>,
    ) -> Result<Value> {
        let request = AccessPaymentRequest {
            payer_id: payer_id.to_string(),
            access_provider_id: access_provider_id.to_string(),
            amount,
            reference: reference.to_string(),
            platform_id: platform_id.unwrap_or("").to_string(),
            platform_fee: platform_fee.unwrap_or(0),
        };
        let response = self.business.access_payment(request).await?;
        let result = response.into_inner();
        Ok(json!({
            "transaction_id": result.transaction_id,
            "reference": result.reference,
            "amount": format_balance(result.amount),
            "amount_cents": result.amount,
            "platform_fee": format_balance(result.platform_fee),
            "platform_fee_cents": result.platform_fee,
            "status": result.status,
            "message": result.message,
        }))
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn role_to_string(role: i32) -> &'static str {
    match role {
        1 => "Access Provider",
        2 => "Banking Partner",
        3 => "Ecosystem Partner",
        4 => "Supplier",
        5 => "Equipment Provider",
        _ => "Unknown",
    }
}

fn account_type_to_string(account_type: i32) -> &'static str {
    match account_type {
        1 => "Standalone",
        2 => "Operating",
        3 => "Receivables",
        4 => "Payables",
        5 => "Escrow",
        6 => "Fees",
        7 => "Usage",
        _ => "Unknown",
    }
}

fn format_balance(balance: i64) -> String {
    let whole = balance / 100;
    let cents = (balance % 100).abs();
    if balance < 0 {
        format!("-{}.{:02}", whole.abs(), cents)
    } else {
        format!("{}.{:02}", whole, cents)
    }
}

// ============================================================================
// MCP Protocol Handlers
// ============================================================================

fn get_server_info() -> Value {
    json!({
        "protocolVersion": "2024-11-05",
        "capabilities": {
            "tools": {}
        },
        "serverInfo": {
            "name": "scalegraph-ledger",
            "version": "1.0.0"
        }
    })
}

fn get_tools_list() -> Value {
    json!({
        "tools": [
            {
                "name": "list_participants",
                "description": "List all participants in the Scalegraph ecosystem. Returns participant IDs, names, and roles (Access Provider, Banking Partner, Ecosystem Partner, Supplier, Equipment Provider).",
                "inputSchema": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            },
            {
                "name": "create_participant",
                "description": "Create a new participant in the ecosystem. Participants can be suppliers, access providers, banking partners, etc.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "id": {
                            "type": "string",
                            "description": "Unique participant ID (e.g., 'acme_supplies', 'new_salon')"
                        },
                        "name": {
                            "type": "string",
                            "description": "Display name (e.g., 'Acme Supplies AB', 'New Salon')"
                        },
                        "role": {
                            "type": "string",
                            "enum": ["access_provider", "banking_partner", "ecosystem_partner", "supplier", "equipment_provider"],
                            "description": "Participant role in the ecosystem"
                        }
                    },
                    "required": ["id", "name", "role"]
                }
            },
            {
                "name": "create_participant_account",
                "description": "Create a ledger account for a participant. Each participant needs accounts to transact (operating for cash, receivables for money owed to them, payables for money they owe, fees for service charges).",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "participant_id": {
                            "type": "string",
                            "description": "Participant ID to create account for"
                        },
                        "account_type": {
                            "type": "string",
                            "enum": ["operating", "receivables", "payables", "escrow", "fees", "usage"],
                            "description": "Type of account: operating (main cash), receivables (A/R), payables (A/P), fees (service charges), escrow (held funds), usage (pay-per-use)"
                        },
                        "initial_balance_cents": {
                            "type": "integer",
                            "description": "Initial balance in cents (e.g., 100000 for $1,000.00). Default: 0"
                        }
                    },
                    "required": ["participant_id", "account_type"]
                }
            },
            {
                "name": "get_participant_accounts",
                "description": "Get all ledger accounts for a participant. Returns account IDs, types (Operating, Receivables, Payables, Fees, etc.), and balances.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "participant_id": {
                            "type": "string",
                            "description": "Participant ID (e.g., 'salon_glamour', 'schampo_etc', 'assa_abloy')"
                        }
                    },
                    "required": ["participant_id"]
                }
            },
            {
                "name": "get_account_balance",
                "description": "Get the current balance of a specific account.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "account_id": {
                            "type": "string",
                            "description": "Account ID in format 'participant_id:account_type' (e.g., 'salon_glamour:operating', 'schampo_etc:receivables')"
                        }
                    },
                    "required": ["account_id"]
                }
            },
            {
                "name": "transfer",
                "description": "Execute an atomic multi-party transfer. All entries must sum to zero. Use positive amounts for credits and negative for debits.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "entries": {
                            "type": "array",
                            "description": "Array of transfer entries, each with account_id and amount_cents",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "account_id": {
                                        "type": "string",
                                        "description": "Account ID"
                                    },
                                    "amount_cents": {
                                        "type": "integer",
                                        "description": "Amount in cents (positive=credit, negative=debit)"
                                    }
                                },
                                "required": ["account_id", "amount_cents"]
                            }
                        },
                        "reference": {
                            "type": "string",
                            "description": "Transaction reference/description"
                        }
                    },
                    "required": ["entries", "reference"]
                }
            },
            {
                "name": "list_transactions",
                "description": "List recent transactions from the ledger. Returns transaction history showing all transfers, invoices, and payments.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "limit": {
                            "type": "integer",
                            "description": "Maximum number of transactions to return (default: 50)"
                        },
                        "account_id": {
                            "type": "string",
                            "description": "Optional: Filter by account ID to see only transactions involving this account"
                        }
                    },
                    "required": []
                }
            },
            {
                "name": "purchase_invoice",
                "description": "Create a B2B purchase invoice. Records debt: increases supplier's receivables and buyer's payables. Use pay_invoice later to settle.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "supplier_id": {
                            "type": "string",
                            "description": "Supplier participant ID (e.g., 'schampo_etc')"
                        },
                        "buyer_id": {
                            "type": "string",
                            "description": "Buyer participant ID (e.g., 'salon_glamour')"
                        },
                        "amount_cents": {
                            "type": "integer",
                            "description": "Invoice amount in cents (e.g., 455000 for $4,550.00)"
                        },
                        "reference": {
                            "type": "string",
                            "description": "Invoice reference (e.g., 'INV-2024-001 ABC Shine 300x')"
                        }
                    },
                    "required": ["supplier_id", "buyer_id", "amount_cents", "reference"]
                }
            },
            {
                "name": "pay_invoice",
                "description": "Pay/settle a B2B invoice. Transfers money from buyer to supplier and clears receivables/payables. All 4 entries are atomic.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "supplier_id": {
                            "type": "string",
                            "description": "Supplier participant ID"
                        },
                        "buyer_id": {
                            "type": "string",
                            "description": "Buyer participant ID"
                        },
                        "amount_cents": {
                            "type": "integer",
                            "description": "Payment amount in cents"
                        },
                        "reference": {
                            "type": "string",
                            "description": "Payment reference (e.g., 'PAY-INV-2024-001')"
                        }
                    },
                    "required": ["supplier_id", "buyer_id", "amount_cents", "reference"]
                }
            },
            {
                "name": "access_payment",
                "description": "Process real-time micro-payment for access control (e.g., door unlock). Debits payer and credits access provider. Optional platform fee.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "payer_id": {
                            "type": "string",
                            "description": "Payer participant ID (e.g., 'salon_glamour')"
                        },
                        "access_provider_id": {
                            "type": "string",
                            "description": "Access provider participant ID (e.g., 'assa_abloy')"
                        },
                        "amount_cents": {
                            "type": "integer",
                            "description": "Access fee in cents (e.g., 800 for $8.00)"
                        },
                        "reference": {
                            "type": "string",
                            "description": "Access reference (e.g., 'DOOR-MAIN-20241215')"
                        },
                        "platform_id": {
                            "type": "string",
                            "description": "Optional: Platform to receive fee (e.g., 'beauty_hosting')"
                        },
                        "platform_fee_cents": {
                            "type": "integer",
                            "description": "Optional: Platform fee in cents (e.g., 50 for $0.50)"
                        }
                    },
                    "required": ["payer_id", "access_provider_id", "amount_cents", "reference"]
                }
            }
        ]
    })
}

fn role_string_to_int(role: &str) -> i32 {
    match role.to_lowercase().as_str() {
        "access_provider" => 1,
        "banking_partner" => 2,
        "ecosystem_partner" => 3,
        "supplier" => 4,
        "equipment_provider" => 5,
        _ => 0,
    }
}

fn account_type_string_to_int(account_type: &str) -> i32 {
    match account_type.to_lowercase().as_str() {
        "standalone" => 1,
        "operating" => 2,
        "receivables" => 3,
        "payables" => 4,
        "escrow" => 5,
        "fees" => 6,
        "usage" => 7,
        _ => 0,
    }
}

async fn handle_tool_call(client: &mut ScalegraphClient, name: &str, args: &Value) -> Result<Value> {
    match name {
        "list_participants" => client.list_participants().await,

        "create_participant" => {
            let id = args.get("id").and_then(|v| v.as_str()).unwrap_or("");
            let name_str = args.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let role_str = args.get("role").and_then(|v| v.as_str()).unwrap_or("ecosystem_partner");
            let role = role_string_to_int(role_str);
            client.create_participant(id, name_str, role).await
        }

        "create_participant_account" => {
            let participant_id = args
                .get("participant_id")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let account_type_str = args
                .get("account_type")
                .and_then(|v| v.as_str())
                .unwrap_or("operating");
            let account_type = account_type_string_to_int(account_type_str);
            let initial_balance = args
                .get("initial_balance_cents")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            client
                .create_participant_account(participant_id, account_type, initial_balance)
                .await
        }

        "get_participant_accounts" => {
            let participant_id = args
                .get("participant_id")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            client.get_participant_accounts(participant_id).await
        }

        "get_account_balance" => {
            let account_id = args.get("account_id").and_then(|v| v.as_str()).unwrap_or("");
            client.get_balance(account_id).await
        }

        "transfer" => {
            let entries: Vec<(String, i64)> = args
                .get("entries")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|e| {
                            let account_id = e.get("account_id")?.as_str()?.to_string();
                            let amount = e.get("amount_cents")?.as_i64()?;
                            Some((account_id, amount))
                        })
                        .collect()
                })
                .unwrap_or_default();
            let reference = args
                .get("reference")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            client.transfer(entries, reference).await
        }

        "list_transactions" => {
            let limit = args.get("limit").and_then(|v| v.as_i64()).map(|v| v as i32);
            let account_id = args.get("account_id").and_then(|v| v.as_str());
            client.list_transactions(limit, account_id).await
        }

        "purchase_invoice" => {
            let supplier_id = args
                .get("supplier_id")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let buyer_id = args.get("buyer_id").and_then(|v| v.as_str()).unwrap_or("");
            let amount = args
                .get("amount_cents")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            let reference = args
                .get("reference")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            client
                .purchase_invoice(supplier_id, buyer_id, amount, reference)
                .await
        }

        "pay_invoice" => {
            let supplier_id = args
                .get("supplier_id")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let buyer_id = args.get("buyer_id").and_then(|v| v.as_str()).unwrap_or("");
            let amount = args
                .get("amount_cents")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            let reference = args
                .get("reference")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            client
                .pay_invoice(supplier_id, buyer_id, amount, reference)
                .await
        }

        "access_payment" => {
            let payer_id = args.get("payer_id").and_then(|v| v.as_str()).unwrap_or("");
            let access_provider_id = args
                .get("access_provider_id")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let amount = args
                .get("amount_cents")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            let reference = args
                .get("reference")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let platform_id = args.get("platform_id").and_then(|v| v.as_str());
            let platform_fee = args.get("platform_fee_cents").and_then(|v| v.as_i64());
            client
                .access_payment(
                    payer_id,
                    access_provider_id,
                    amount,
                    reference,
                    platform_id,
                    platform_fee,
                )
                .await
        }

        _ => Ok(json!({"error": format!("Unknown tool: {}", name)})),
    }
}

async fn handle_request(
    client: &mut ScalegraphClient,
    request: JsonRpcRequest,
) -> Option<JsonRpcResponse> {
    // Notifications don't get responses
    if request.method.starts_with("notifications/") {
        return None;
    }

    let id = request.id.unwrap_or(Value::Null);

    let result = match request.method.as_str() {
        "initialize" => Ok(get_server_info()),
        "tools/list" => Ok(get_tools_list()),
        "tools/call" => {
            if let Some(params) = request.params {
                let name = params.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let empty_args = json!({});
                let args = params.get("arguments").unwrap_or(&empty_args);
                match handle_tool_call(client, name, args).await {
                    Ok(result) => Ok(json!({
                        "content": [{
                            "type": "text",
                            "text": serde_json::to_string_pretty(&result).unwrap_or_default()
                        }]
                    })),
                    Err(e) => Ok(json!({
                        "content": [{
                            "type": "text",
                            "text": format!("Error: {}", e)
                        }],
                        "isError": true
                    })),
                }
            } else {
                Err("Missing params")
            }
        }
        _ => Err("Method not found"),
    };

    Some(match result {
        Ok(r) => JsonRpcResponse {
            jsonrpc: "2.0".to_string(),
            id,
            result: Some(r),
            error: None,
        },
        Err(msg) => JsonRpcResponse {
            jsonrpc: "2.0".to_string(),
            id,
            result: None,
            error: Some(JsonRpcError {
                code: -32601,
                message: msg.to_string(),
            }),
        },
    })
}

#[tokio::main]
async fn main() -> Result<()> {
    // Use environment variable or default to localhost
    let grpc_url =
        std::env::var("SCALEGRAPH_GRPC_URL").unwrap_or_else(|_| "http://localhost:50051".to_string());

    // Debug info only when SCALEGRAPH_DEBUG is set
    if std::env::var("SCALEGRAPH_DEBUG").is_ok() {
        eprintln!("Scalegraph Ledger MCP Server v1.0.0");
        eprintln!("gRPC URL: {}", grpc_url);
    }

    // Connect to gRPC server
    let mut client = match ScalegraphClient::connect(&grpc_url).await {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Failed to connect to gRPC server at {}: {}", grpc_url, e);
            eprintln!("Make sure the Scalegraph Elixir server is running.");
            std::process::exit(1);
        }
    };

    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line in stdin.lock().lines() {
        let line = line?;
        if line.is_empty() {
            continue;
        }

        match serde_json::from_str::<JsonRpcRequest>(&line) {
            Ok(request) => {
                // Only send response if not a notification
                if let Some(response) = handle_request(&mut client, request).await {
                    let response_json = serde_json::to_string(&response)?;
                    writeln!(stdout, "{}", response_json)?;
                    stdout.flush()?;
                }
            }
            Err(e) => {
                // Return JSON-RPC error
                let error_response = JsonRpcResponse {
                    jsonrpc: "2.0".to_string(),
                    id: Value::Null,
                    result: None,
                    error: Some(JsonRpcError {
                        code: -32700,
                        message: format!("Parse error: {}", e),
                    }),
                };
                let response_json = serde_json::to_string(&error_response)?;
                writeln!(stdout, "{}", response_json)?;
                stdout.flush()?;
            }
        }
    }

    Ok(())
}
