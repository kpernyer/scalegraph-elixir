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

#[allow(dead_code)]
pub mod common {
    tonic::include_proto!("scalegraph.common");
}

#[allow(dead_code)]
pub mod ledger {
    tonic::include_proto!("scalegraph.ledger");
}

#[allow(dead_code)]
pub mod business {
    tonic::include_proto!("scalegraph.business");
}

#[allow(dead_code)]
pub mod smartcontracts {
    tonic::include_proto!("scalegraph.smartcontracts");
}

use anyhow::Result;
use common::TransferEntry;
use ledger::{
    ledger_service_client::LedgerServiceClient, GetBalanceRequest, ListTransactionsRequest,
    TransferRequest,
};
use business::{
    business_service_client::BusinessServiceClient, participant_service_client::ParticipantServiceClient,
    AccessPaymentRequest, CreateLoanRequest, CreateParticipantAccountRequest,
    CreateParticipantRequest, GetOutstandingLoansRequest, GetParticipantAccountsRequest,
    GetTotalDebtRequest, ListParticipantsRequest, PayInvoiceRequest, PurchaseInvoiceRequest,
    RepayLoanRequest,
};
use smartcontracts::{
    smart_contract_service_client::SmartContractServiceClient,
    ContractType, ContractStatus,
    CreateInvoiceContractRequest, CreateSubscriptionContractRequest,
    CreateConditionalPaymentRequest, CreateRevenueShareContractRequest,
    GetContractRequest, ListContractsRequest, ExecuteContractRequest,
    UpdateContractStatusRequest, RevenueShareParty,
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
    contracts: SmartContractServiceClient<Channel>,
}

impl ScalegraphClient {
    async fn connect(addr: &str) -> Result<Self> {
        let channel = Channel::from_shared(addr.to_string())?.connect().await?;

        Ok(Self {
            ledger: LedgerServiceClient::new(channel.clone()),
            participant: ParticipantServiceClient::new(channel.clone()),
            business: BusinessServiceClient::new(channel.clone()),
            contracts: SmartContractServiceClient::new(channel),
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
            about: String::new(),
            contact: None,
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

    async fn create_loan(
        &mut self,
        lender_id: &str,
        borrower_id: &str,
        amount: i64,
        reference: &str,
    ) -> Result<Value> {
        let request = CreateLoanRequest {
            lender_id: lender_id.to_string(),
            borrower_id: borrower_id.to_string(),
            principal_cents: amount,
            annual_interest_rate: 0.05, // Default 5% annual interest
            term_months: 60, // Default 60 months (5 years)
            reference: reference.to_string(),
        };
        let response = self.business.create_loan(request).await?;
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

    async fn repay_loan(
        &mut self,
        lender_id: &str,
        borrower_id: &str,
        amount: i64,
        reference: &str,
    ) -> Result<Value> {
        let request = RepayLoanRequest {
            lender_id: lender_id.to_string(),
            borrower_id: borrower_id.to_string(),
            amount,
            reference: reference.to_string(),
        };
        let response = self.business.repay_loan(request).await?;
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

    async fn get_outstanding_loans(&mut self, lender_id: &str) -> Result<Value> {
        let request = GetOutstandingLoansRequest {
            lender_id: lender_id.to_string(),
        };
        let response = self.business.get_outstanding_loans(request).await?;
        let result = response.into_inner();
        Ok(json!({
            "lender_id": result.lender_id,
            "total_outstanding": format_balance(result.total_outstanding),
            "total_outstanding_cents": result.total_outstanding,
        }))
    }

    async fn get_total_debt(&mut self, borrower_id: &str) -> Result<Value> {
        let request = GetTotalDebtRequest {
            borrower_id: borrower_id.to_string(),
        };
        let response = self.business.get_total_debt(request).await?;
        let result = response.into_inner();
        Ok(json!({
            "borrower_id": result.borrower_id,
            "total_debt": format_balance(result.total_debt),
            "total_debt_cents": result.total_debt,
        }))
    }

    // Smart Contract operations

    async fn create_invoice_contract(
        &mut self,
        supplier_id: &str,
        buyer_id: &str,
        amount_cents: i64,
        issue_date: i64,
        due_date: i64,
        payment_terms: &str,
        auto_debit: bool,
        late_fee_cents: i64,
        reference: &str,
    ) -> Result<Value> {
        let request = CreateInvoiceContractRequest {
            supplier_id: supplier_id.to_string(),
            buyer_id: buyer_id.to_string(),
            amount_cents,
            issue_date,
            due_date,
            payment_terms: payment_terms.to_string(),
            auto_debit,
            late_fee_cents,
            reference: reference.to_string(),
            metadata: std::collections::HashMap::new(),
        };
        let response = self.contracts.create_invoice_contract(request).await?;
        let contract = response.into_inner();
        Ok(json!({
            "id": contract.id,
            "supplier_id": contract.supplier_id,
            "buyer_id": contract.buyer_id,
            "amount_cents": contract.amount_cents,
            "amount": format_balance(contract.amount_cents),
            "issue_date": contract.issue_date,
            "due_date": contract.due_date,
            "payment_terms": contract.payment_terms,
            "auto_debit": contract.auto_debit,
            "late_fee_cents": contract.late_fee_cents,
            "status": contract.status,
            "reference": contract.reference,
        }))
    }

    async fn get_invoice_contract(&mut self, contract_id: &str) -> Result<Value> {
        let request = GetContractRequest {
            contract_id: contract_id.to_string(),
            contract_type: ContractType::Invoice as i32,
        };
        let response = self.contracts.get_invoice_contract(request).await?;
        let contract = response.into_inner();
        Ok(json!({
            "id": contract.id,
            "supplier_id": contract.supplier_id,
            "buyer_id": contract.buyer_id,
            "amount_cents": contract.amount_cents,
            "amount": format_balance(contract.amount_cents),
            "issue_date": contract.issue_date,
            "due_date": contract.due_date,
            "payment_terms": contract.payment_terms,
            "auto_debit": contract.auto_debit,
            "late_fee_cents": contract.late_fee_cents,
            "status": contract.status,
            "reference": contract.reference,
            "created_at": contract.created_at,
            "paid_at": contract.paid_at,
        }))
    }

    async fn create_subscription_contract(
        &mut self,
        provider_id: &str,
        subscriber_id: &str,
        monthly_fee_cents: i64,
        billing_date: &str,
        auto_debit: bool,
        cancellation_notice_days: i32,
        start_date: i64,
        end_date: Option<i64>,
    ) -> Result<Value> {
        let request = CreateSubscriptionContractRequest {
            provider_id: provider_id.to_string(),
            subscriber_id: subscriber_id.to_string(),
            monthly_fee_cents,
            billing_date: billing_date.to_string(),
            auto_debit,
            cancellation_notice_days,
            start_date,
            end_date: end_date.unwrap_or(0),
            metadata: std::collections::HashMap::new(),
        };
        let response = self.contracts.create_subscription_contract(request).await?;
        let contract = response.into_inner();
        Ok(json!({
            "id": contract.id,
            "provider_id": contract.provider_id,
            "subscriber_id": contract.subscriber_id,
            "monthly_fee_cents": contract.monthly_fee_cents,
            "monthly_fee": format_balance(contract.monthly_fee_cents),
            "billing_date": contract.billing_date,
            "auto_debit": contract.auto_debit,
            "cancellation_notice_days": contract.cancellation_notice_days,
            "start_date": contract.start_date,
            "end_date": contract.end_date,
            "status": contract.status,
            "next_billing_date": contract.next_billing_date,
        }))
    }

    async fn get_subscription_contract(&mut self, contract_id: &str) -> Result<Value> {
        let request = GetContractRequest {
            contract_id: contract_id.to_string(),
            contract_type: ContractType::Subscription as i32,
        };
        let response = self.contracts.get_subscription_contract(request).await?;
        let contract = response.into_inner();
        Ok(json!({
            "id": contract.id,
            "provider_id": contract.provider_id,
            "subscriber_id": contract.subscriber_id,
            "monthly_fee_cents": contract.monthly_fee_cents,
            "monthly_fee": format_balance(contract.monthly_fee_cents),
            "billing_date": contract.billing_date,
            "auto_debit": contract.auto_debit,
            "cancellation_notice_days": contract.cancellation_notice_days,
            "start_date": contract.start_date,
            "end_date": contract.end_date,
            "status": contract.status,
            "next_billing_date": contract.next_billing_date,
        }))
    }

    async fn create_conditional_payment(
        &mut self,
        payer_id: &str,
        receiver_id: &str,
        amount_cents: i64,
        condition_type: &str,
        trigger: &str,
    ) -> Result<Value> {
        let request = CreateConditionalPaymentRequest {
            payer_id: payer_id.to_string(),
            receiver_id: receiver_id.to_string(),
            amount_cents,
            condition_type: condition_type.to_string(),
            trigger: trigger.to_string(),
            condition_parameters: std::collections::HashMap::new(),
            metadata: std::collections::HashMap::new(),
        };
        let response = self.contracts.create_conditional_payment(request).await?;
        let contract = response.into_inner();
        Ok(json!({
            "id": contract.id,
            "payer_id": contract.payer_id,
            "receiver_id": contract.receiver_id,
            "amount_cents": contract.amount_cents,
            "amount": format_balance(contract.amount_cents),
            "condition_type": contract.condition_type,
            "trigger": contract.trigger,
            "status": contract.status,
            "created_at": contract.created_at,
        }))
    }

    async fn get_conditional_payment(&mut self, contract_id: &str) -> Result<Value> {
        let request = GetContractRequest {
            contract_id: contract_id.to_string(),
            contract_type: ContractType::ConditionalPayment as i32,
        };
        let response = self.contracts.get_conditional_payment(request).await?;
        let contract = response.into_inner();
        Ok(json!({
            "id": contract.id,
            "payer_id": contract.payer_id,
            "receiver_id": contract.receiver_id,
            "amount_cents": contract.amount_cents,
            "amount": format_balance(contract.amount_cents),
            "condition_type": contract.condition_type,
            "trigger": contract.trigger,
            "status": contract.status,
            "created_at": contract.created_at,
            "executed_at": contract.executed_at,
        }))
    }

    async fn create_revenue_share_contract(
        &mut self,
        transaction_type: &str,
        parties: Vec<(String, f64)>,
        auto_split: bool,
    ) -> Result<Value> {
        let revenue_parties: Vec<RevenueShareParty> = parties
            .into_iter()
            .map(|(participant_id, share)| RevenueShareParty {
                participant_id,
                share,
            })
            .collect();
        let request = CreateRevenueShareContractRequest {
            transaction_type: transaction_type.to_string(),
            parties: revenue_parties,
            auto_split,
            metadata: std::collections::HashMap::new(),
        };
        let response = self.contracts.create_revenue_share_contract(request).await?;
        let contract = response.into_inner();
        let parties_json: Vec<Value> = contract
            .parties
            .iter()
            .map(|p| {
                json!({
                    "participant_id": p.participant_id,
                    "share": p.share,
                    "share_percent": (p.share * 100.0) as i32,
                })
            })
            .collect();
        Ok(json!({
            "id": contract.id,
            "transaction_type": contract.transaction_type,
            "parties": parties_json,
            "auto_split": contract.auto_split,
            "status": contract.status,
            "created_at": contract.created_at,
        }))
    }

    async fn get_revenue_share_contract(&mut self, contract_id: &str) -> Result<Value> {
        let request = GetContractRequest {
            contract_id: contract_id.to_string(),
            contract_type: ContractType::RevenueShare as i32,
        };
        let response = self.contracts.get_revenue_share_contract(request).await?;
        let contract = response.into_inner();
        let parties_json: Vec<Value> = contract
            .parties
            .iter()
            .map(|p| {
                json!({
                    "participant_id": p.participant_id,
                    "share": p.share,
                    "share_percent": (p.share * 100.0) as i32,
                })
            })
            .collect();
        Ok(json!({
            "id": contract.id,
            "transaction_type": contract.transaction_type,
            "parties": parties_json,
            "auto_split": contract.auto_split,
            "status": contract.status,
            "created_at": contract.created_at,
            "last_distributed_at": contract.last_distributed_at,
        }))
    }

    async fn list_contracts(
        &mut self,
        contract_type: Option<i32>,
        status: Option<&str>,
        participant_id: Option<&str>,
        limit: Option<i32>,
    ) -> Result<Value> {
        let request = ListContractsRequest {
            contract_type: contract_type.unwrap_or(0),
            status: status.unwrap_or("").to_string(),
            participant_id: participant_id.unwrap_or("").to_string(),
            limit: limit.unwrap_or(100),
        };
        let response = self.contracts.list_contracts(request).await?;
        let contracts = response.into_inner().contracts;
        use smartcontracts::contract_response::Contract;
        let contracts_json: Vec<Value> = contracts
            .iter()
            .filter_map(|c| {
                match c.contract.as_ref() {
                    Some(Contract::Invoice(inv)) => Some(json!({
                        "type": "invoice",
                        "contract": {
                            "id": inv.id,
                            "supplier_id": inv.supplier_id,
                            "buyer_id": inv.buyer_id,
                            "amount_cents": inv.amount_cents,
                            "status": inv.status,
                            "reference": inv.reference,
                        }
                    })),
                    Some(Contract::Subscription(sub)) => Some(json!({
                        "type": "subscription",
                        "contract": {
                            "id": sub.id,
                            "provider_id": sub.provider_id,
                            "subscriber_id": sub.subscriber_id,
                            "monthly_fee_cents": sub.monthly_fee_cents,
                            "status": sub.status,
                        }
                    })),
                    Some(Contract::ConditionalPayment(cp)) => Some(json!({
                        "type": "conditional_payment",
                        "contract": {
                            "id": cp.id,
                            "payer_id": cp.payer_id,
                            "receiver_id": cp.receiver_id,
                            "amount_cents": cp.amount_cents,
                            "status": cp.status,
                        }
                    })),
                    Some(Contract::RevenueShare(rs)) => Some(json!({
                        "type": "revenue_share",
                        "contract": {
                            "id": rs.id,
                            "transaction_type": rs.transaction_type,
                            "status": rs.status,
                        }
                    })),
                    None => None,
                }
            })
            .collect();
        Ok(json!({ "contracts": contracts_json }))
    }

    async fn execute_contract(
        &mut self,
        contract_id: &str,
        contract_type: i32,
    ) -> Result<Value> {
        let request = ExecuteContractRequest {
            contract_id: contract_id.to_string(),
            contract_type,
        };
        let response = self.contracts.execute_contract(request).await?;
        let result = response.into_inner();
        Ok(json!({
            "contract_id": result.contract_id,
            "executed": result.executed,
            "message": result.message,
            "transaction_ids": result.transaction_ids,
        }))
    }

    async fn update_contract_status(
        &mut self,
        contract_id: &str,
        contract_type: i32,
        status: i32,
    ) -> Result<Value> {
        let request = UpdateContractStatusRequest {
            contract_id: contract_id.to_string(),
            contract_type,
            status,
        };
        let response = self.contracts.update_contract_status(request).await?;
        let contract_response = response.into_inner();
        use smartcontracts::contract_response::Contract;
        let contract_json = match contract_response.contract.as_ref() {
            Some(Contract::Invoice(inv)) => json!({
                "type": "invoice",
                "id": inv.id,
                "status": inv.status,
            }),
            Some(Contract::Subscription(sub)) => json!({
                "type": "subscription",
                "id": sub.id,
                "status": sub.status,
            }),
            Some(Contract::ConditionalPayment(cp)) => json!({
                "type": "conditional_payment",
                "id": cp.id,
                "status": cp.status,
            }),
            Some(Contract::RevenueShare(rs)) => json!({
                "type": "revenue_share",
                "id": rs.id,
                "status": rs.status,
            }),
            None => json!({"type": "unknown"}),
        };
        Ok(json!({ "contract": contract_json }))
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
            },
            {
                "name": "create_loan",
                "description": "Create a loan with formal obligation tracking. Lender provides funds and records receivables/payables. All 4 entries (lender operating, borrower operating, lender receivables, borrower payables) are atomic.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "lender_id": {
                            "type": "string",
                            "description": "Lender participant ID (e.g., 'seb')"
                        },
                        "borrower_id": {
                            "type": "string",
                            "description": "Borrower participant ID (e.g., 'salon_glamour')"
                        },
                        "amount_cents": {
                            "type": "integer",
                            "description": "Loan amount in cents (e.g., 150023 for $1,500.23)"
                        },
                        "reference": {
                            "type": "string",
                            "description": "Loan reference (e.g., 'LOAN-2024-001')"
                        }
                    },
                    "required": ["lender_id", "borrower_id", "amount_cents", "reference"]
                }
            },
            {
                "name": "repay_loan",
                "description": "Repay a loan and clear obligations. Reverses receivables/payables entries atomically.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "lender_id": {
                            "type": "string",
                            "description": "Lender participant ID"
                        },
                        "borrower_id": {
                            "type": "string",
                            "description": "Borrower participant ID"
                        },
                        "amount_cents": {
                            "type": "integer",
                            "description": "Repayment amount in cents"
                        },
                        "reference": {
                            "type": "string",
                            "description": "Repayment reference (e.g., 'REPAY-LOAN-2024-001')"
                        }
                    },
                    "required": ["lender_id", "borrower_id", "amount_cents", "reference"]
                }
            },
            {
                "name": "get_outstanding_loans",
                "description": "Get total outstanding loans for a lender. Returns the positive balance in lender's receivables account.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "lender_id": {
                            "type": "string",
                            "description": "Lender participant ID (e.g., 'seb')"
                        }
                    },
                    "required": ["lender_id"]
                }
            },
            {
                "name": "get_total_debt",
                "description": "Get total debt for a borrower. Returns the absolute value of negative balance in borrower's payables account.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "borrower_id": {
                            "type": "string",
                            "description": "Borrower participant ID (e.g., 'salon_glamour')"
                        }
                    },
                    "required": ["borrower_id"]
                }
            },
            {
                "name": "create_invoice_contract",
                "description": "Create a smart invoice contract with automation (auto-debit on due date, late fees). Higher-level than purchase_invoice - includes contract management.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "supplier_id": {"type": "string", "description": "Supplier participant ID"},
                        "buyer_id": {"type": "string", "description": "Buyer participant ID"},
                        "amount_cents": {"type": "integer", "description": "Invoice amount in cents"},
                        "issue_date": {"type": "integer", "description": "Issue date (Unix timestamp in milliseconds)"},
                        "due_date": {"type": "integer", "description": "Due date (Unix timestamp in milliseconds)"},
                        "payment_terms": {"type": "string", "description": "Payment terms (e.g., 'Net 30')"},
                        "auto_debit": {"type": "boolean", "description": "Enable automatic debit on due date"},
                        "late_fee_cents": {"type": "integer", "description": "Late fee in cents if not paid by due date"},
                        "reference": {"type": "string", "description": "Invoice reference"}
                    },
                    "required": ["supplier_id", "buyer_id", "amount_cents", "issue_date", "due_date", "reference"]
                }
            },
            {
                "name": "get_invoice_contract",
                "description": "Get details of an invoice contract by ID.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "contract_id": {"type": "string", "description": "Invoice contract ID"}
                    },
                    "required": ["contract_id"]
                }
            },
            {
                "name": "create_subscription_contract",
                "description": "Create a subscription contract with recurring billing (e.g., monthly SaaS fee). Supports auto-debit and cancellation notice periods.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "provider_id": {"type": "string", "description": "Service provider participant ID"},
                        "subscriber_id": {"type": "string", "description": "Subscriber participant ID"},
                        "monthly_fee_cents": {"type": "integer", "description": "Monthly subscription fee in cents"},
                        "billing_date": {"type": "string", "description": "Billing date pattern (e.g., 'every 1st', 'every 15th')"},
                        "auto_debit": {"type": "boolean", "description": "Enable automatic monthly debit"},
                        "cancellation_notice_days": {"type": "integer", "description": "Days notice required for cancellation"},
                        "start_date": {"type": "integer", "description": "Start date (Unix timestamp in milliseconds)"},
                        "end_date": {"type": "integer", "description": "Optional end date (Unix timestamp in milliseconds)"}
                    },
                    "required": ["provider_id", "subscriber_id", "monthly_fee_cents", "billing_date", "start_date"]
                }
            },
            {
                "name": "get_subscription_contract",
                "description": "Get details of a subscription contract by ID.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "contract_id": {"type": "string", "description": "Subscription contract ID"}
                    },
                    "required": ["contract_id"]
                }
            },
            {
                "name": "create_conditional_payment",
                "description": "Create a conditional payment contract that executes when conditions are met (e.g., 'if_service_completed'). Payment is held until trigger condition is satisfied.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "payer_id": {"type": "string", "description": "Payer participant ID"},
                        "receiver_id": {"type": "string", "description": "Receiver participant ID"},
                        "amount_cents": {"type": "integer", "description": "Payment amount in cents"},
                        "condition_type": {"type": "string", "description": "Condition type (e.g., 'if_service_completed')"},
                        "trigger": {"type": "string", "description": "Trigger condition (e.g., \"status = 'completed'\")"}
                    },
                    "required": ["payer_id", "receiver_id", "amount_cents", "condition_type", "trigger"]
                }
            },
            {
                "name": "get_conditional_payment",
                "description": "Get details of a conditional payment contract by ID.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "contract_id": {"type": "string", "description": "Conditional payment contract ID"}
                    },
                    "required": ["contract_id"]
                }
            },
            {
                "name": "create_revenue_share_contract",
                "description": "Create a revenue share contract that automatically splits revenue from transactions among multiple parties (e.g., 70% salon, 20% supplier, 10% platform).",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "transaction_type": {"type": "string", "description": "Transaction type to apply revenue share to (e.g., 'service_sale')"},
                        "parties": {
                            "type": "array",
                            "description": "Array of parties with their share percentages",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "participant_id": {"type": "string"},
                                    "share": {"type": "number", "description": "Share as decimal (e.g., 0.70 for 70%)"}
                                },
                                "required": ["participant_id", "share"]
                            }
                        },
                        "auto_split": {"type": "boolean", "description": "Enable automatic revenue splitting on each transaction"}
                    },
                    "required": ["transaction_type", "parties"]
                }
            },
            {
                "name": "get_revenue_share_contract",
                "description": "Get details of a revenue share contract by ID.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "contract_id": {"type": "string", "description": "Revenue share contract ID"}
                    },
                    "required": ["contract_id"]
                }
            },
            {
                "name": "list_contracts",
                "description": "List all contracts with optional filters by type, status, or participant.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "contract_type": {
                            "type": "string",
                            "enum": ["loan", "invoice", "subscription", "conditional_payment", "revenue_share"],
                            "description": "Optional: Filter by contract type"
                        },
                        "status": {"type": "string", "description": "Optional: Filter by status (e.g., 'active', 'completed')"},
                        "participant_id": {"type": "string", "description": "Optional: Filter by participant ID (any role)"},
                        "limit": {"type": "integer", "description": "Maximum results (default: 100)"}
                    },
                    "required": []
                }
            },
            {
                "name": "execute_contract",
                "description": "Manually execute a contract (e.g., trigger conditional payment when conditions are met, process subscription billing).",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "contract_id": {"type": "string", "description": "Contract ID"},
                        "contract_type": {
                            "type": "string",
                            "enum": ["loan", "invoice", "subscription", "conditional_payment", "revenue_share"],
                            "description": "Contract type"
                        }
                    },
                    "required": ["contract_id", "contract_type"]
                }
            },
            {
                "name": "update_contract_status",
                "description": "Update the status of a contract (e.g., pause, cancel, complete).",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "contract_id": {"type": "string", "description": "Contract ID"},
                        "contract_type": {
                            "type": "string",
                            "enum": ["loan", "invoice", "subscription", "conditional_payment", "revenue_share"],
                            "description": "Contract type"
                        },
                        "status": {
                            "type": "string",
                            "enum": ["active", "paused", "completed", "cancelled"],
                            "description": "New status"
                        }
                    },
                    "required": ["contract_id", "contract_type", "status"]
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

fn contract_type_string_to_int(contract_type: &str) -> i32 {
    match contract_type.to_lowercase().as_str() {
        "loan" => ContractType::Loan as i32,
        "invoice" => ContractType::Invoice as i32,
        "subscription" => ContractType::Subscription as i32,
        "conditional_payment" => ContractType::ConditionalPayment as i32,
        "revenue_share" => ContractType::RevenueShare as i32,
        _ => 0,
    }
}

fn contract_status_string_to_int(status: &str) -> i32 {
    match status.to_lowercase().as_str() {
        "active" => ContractStatus::Active as i32,
        "paused" => ContractStatus::Paused as i32,
        "completed" => ContractStatus::Completed as i32,
        "cancelled" => ContractStatus::Cancelled as i32,
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

        "create_loan" => {
            let lender_id = args.get("lender_id").and_then(|v| v.as_str()).unwrap_or("");
            let borrower_id = args.get("borrower_id").and_then(|v| v.as_str()).unwrap_or("");
            let amount = args
                .get("amount_cents")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            let reference = args
                .get("reference")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            client
                .create_loan(lender_id, borrower_id, amount, reference)
                .await
        }

        "repay_loan" => {
            let lender_id = args.get("lender_id").and_then(|v| v.as_str()).unwrap_or("");
            let borrower_id = args.get("borrower_id").and_then(|v| v.as_str()).unwrap_or("");
            let amount = args
                .get("amount_cents")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            let reference = args
                .get("reference")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            client
                .repay_loan(lender_id, borrower_id, amount, reference)
                .await
        }

        "get_outstanding_loans" => {
            let lender_id = args.get("lender_id").and_then(|v| v.as_str()).unwrap_or("");
            client.get_outstanding_loans(lender_id).await
        }

        "get_total_debt" => {
            let borrower_id = args.get("borrower_id").and_then(|v| v.as_str()).unwrap_or("");
            client.get_total_debt(borrower_id).await
        }

        "create_invoice_contract" => {
            let supplier_id = args.get("supplier_id").and_then(|v| v.as_str()).unwrap_or("");
            let buyer_id = args.get("buyer_id").and_then(|v| v.as_str()).unwrap_or("");
            let amount_cents = args.get("amount_cents").and_then(|v| v.as_i64()).unwrap_or(0);
            let issue_date = args.get("issue_date").and_then(|v| v.as_i64()).unwrap_or(0);
            let due_date = args.get("due_date").and_then(|v| v.as_i64()).unwrap_or(0);
            let payment_terms = args.get("payment_terms").and_then(|v| v.as_str()).unwrap_or("Net 30");
            let auto_debit = args.get("auto_debit").and_then(|v| v.as_bool()).unwrap_or(false);
            let late_fee_cents = args.get("late_fee_cents").and_then(|v| v.as_i64()).unwrap_or(0);
            let reference = args.get("reference").and_then(|v| v.as_str()).unwrap_or("");
            client
                .create_invoice_contract(
                    supplier_id,
                    buyer_id,
                    amount_cents,
                    issue_date,
                    due_date,
                    payment_terms,
                    auto_debit,
                    late_fee_cents,
                    reference,
                )
                .await
        }

        "get_invoice_contract" => {
            let contract_id = args.get("contract_id").and_then(|v| v.as_str()).unwrap_or("");
            client.get_invoice_contract(contract_id).await
        }

        "create_subscription_contract" => {
            let provider_id = args.get("provider_id").and_then(|v| v.as_str()).unwrap_or("");
            let subscriber_id = args.get("subscriber_id").and_then(|v| v.as_str()).unwrap_or("");
            let monthly_fee_cents = args.get("monthly_fee_cents").and_then(|v| v.as_i64()).unwrap_or(0);
            let billing_date = args.get("billing_date").and_then(|v| v.as_str()).unwrap_or("every 1st");
            let auto_debit = args.get("auto_debit").and_then(|v| v.as_bool()).unwrap_or(true);
            let cancellation_notice_days = args.get("cancellation_notice_days").and_then(|v| v.as_i64()).map(|v| v as i32).unwrap_or(30);
            let start_date = args.get("start_date").and_then(|v| v.as_i64()).unwrap_or(0);
            let end_date = args.get("end_date").and_then(|v| v.as_i64());
            client
                .create_subscription_contract(
                    provider_id,
                    subscriber_id,
                    monthly_fee_cents,
                    billing_date,
                    auto_debit,
                    cancellation_notice_days,
                    start_date,
                    end_date,
                )
                .await
        }

        "get_subscription_contract" => {
            let contract_id = args.get("contract_id").and_then(|v| v.as_str()).unwrap_or("");
            client.get_subscription_contract(contract_id).await
        }

        "create_conditional_payment" => {
            let payer_id = args.get("payer_id").and_then(|v| v.as_str()).unwrap_or("");
            let receiver_id = args.get("receiver_id").and_then(|v| v.as_str()).unwrap_or("");
            let amount_cents = args.get("amount_cents").and_then(|v| v.as_i64()).unwrap_or(0);
            let condition_type = args.get("condition_type").and_then(|v| v.as_str()).unwrap_or("");
            let trigger = args.get("trigger").and_then(|v| v.as_str()).unwrap_or("");
            client
                .create_conditional_payment(payer_id, receiver_id, amount_cents, condition_type, trigger)
                .await
        }

        "get_conditional_payment" => {
            let contract_id = args.get("contract_id").and_then(|v| v.as_str()).unwrap_or("");
            client.get_conditional_payment(contract_id).await
        }

        "create_revenue_share_contract" => {
            let transaction_type = args.get("transaction_type").and_then(|v| v.as_str()).unwrap_or("");
            let parties: Vec<(String, f64)> = args
                .get("parties")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|p| {
                            let participant_id = p.get("participant_id")?.as_str()?.to_string();
                            let share = p.get("share")?.as_f64()?;
                            Some((participant_id, share))
                        })
                        .collect()
                })
                .unwrap_or_default();
            let auto_split = args.get("auto_split").and_then(|v| v.as_bool()).unwrap_or(true);
            client
                .create_revenue_share_contract(transaction_type, parties, auto_split)
                .await
        }

        "get_revenue_share_contract" => {
            let contract_id = args.get("contract_id").and_then(|v| v.as_str()).unwrap_or("");
            client.get_revenue_share_contract(contract_id).await
        }

        "list_contracts" => {
            let contract_type_str = args.get("contract_type").and_then(|v| v.as_str());
            let contract_type = contract_type_str.map(|s| contract_type_string_to_int(s));
            let status = args.get("status").and_then(|v| v.as_str());
            let participant_id = args.get("participant_id").and_then(|v| v.as_str());
            let limit = args.get("limit").and_then(|v| v.as_i64()).map(|v| v as i32);
            client.list_contracts(contract_type, status, participant_id, limit).await
        }

        "execute_contract" => {
            let contract_id = args.get("contract_id").and_then(|v| v.as_str()).unwrap_or("");
            let contract_type_str = args.get("contract_type").and_then(|v| v.as_str()).unwrap_or("");
            let contract_type = contract_type_string_to_int(contract_type_str);
            client.execute_contract(contract_id, contract_type).await
        }

        "update_contract_status" => {
            let contract_id = args.get("contract_id").and_then(|v| v.as_str()).unwrap_or("");
            let contract_type_str = args.get("contract_type").and_then(|v| v.as_str()).unwrap_or("");
            let contract_type = contract_type_string_to_int(contract_type_str);
            let status_str = args.get("status").and_then(|v| v.as_str()).unwrap_or("");
            let status = contract_status_string_to_int(status_str);
            client.update_contract_status(contract_id, contract_type, status).await
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
