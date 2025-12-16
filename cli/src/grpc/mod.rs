//! gRPC Client Module
//!
//! This module provides the gRPC client implementation for communicating with
//! the Scalegraph ledger server. It includes:
//!
//! - `ScalegraphClient`: Main client struct that wraps all service clients
//! - Service-specific methods for Participant, Ledger, and Business operations
//! - Type conversions between Rust types and protobuf messages
//!
//! The client handles connection management, request/response serialization,
//! and error handling for all gRPC operations.

#[allow(dead_code)]
pub mod ledger {
    tonic::include_proto!("scalegraph.ledger");
}

use anyhow::Result;
use ledger::{
    business_service_client::BusinessServiceClient, ledger_service_client::LedgerServiceClient,
    participant_service_client::ParticipantServiceClient, AccessPaymentRequest, Account,
    BusinessTransactionResponse, CreditRequest, DebitRequest, GetAccountRequest, GetBalanceRequest,
    GetParticipantAccountsRequest, GetParticipantRequest, ListParticipantsRequest,
    ListTransactionsRequest, Participant, PayInvoiceRequest, PurchaseInvoiceRequest, Transaction,
    TransferEntry, TransferRequest,
};
use tonic::transport::Channel;

pub use ledger::{AccountType, ParticipantRole};

#[derive(Clone)]
pub struct ScalegraphClient {
    ledger: LedgerServiceClient<Channel>,
    participant: ParticipantServiceClient<Channel>,
    business: BusinessServiceClient<Channel>,
}

impl ScalegraphClient {
    pub async fn connect(addr: &str) -> Result<Self> {
        let channel = Channel::from_shared(addr.to_string())?.connect().await?;

        Ok(Self {
            ledger: LedgerServiceClient::new(channel.clone()),
            participant: ParticipantServiceClient::new(channel.clone()),
            business: BusinessServiceClient::new(channel),
        })
    }

    // Participant operations

    pub async fn list_participants(
        &mut self,
        role: Option<ParticipantRole>,
    ) -> Result<Vec<Participant>> {
        let request = ListParticipantsRequest {
            role: role.map(|r| r as i32).unwrap_or(0),
        };
        let response = self.participant.list_participants(request).await?;
        Ok(response.into_inner().participants)
    }

    #[allow(dead_code)]
    pub async fn get_participant(&mut self, id: &str) -> Result<Participant> {
        let request = GetParticipantRequest {
            participant_id: id.to_string(),
        };
        let response = self.participant.get_participant(request).await?;
        Ok(response.into_inner())
    }

    pub async fn get_participant_accounts(&mut self, participant_id: &str) -> Result<Vec<Account>> {
        let request = GetParticipantAccountsRequest {
            participant_id: participant_id.to_string(),
        };
        let response = self.participant.get_participant_accounts(request).await?;
        Ok(response.into_inner().accounts)
    }

    // Ledger operations

    #[allow(dead_code)]
    pub async fn get_account(&mut self, account_id: &str) -> Result<Account> {
        let request = GetAccountRequest {
            account_id: account_id.to_string(),
        };
        let response = self.ledger.get_account(request).await?;
        Ok(response.into_inner())
    }

    #[allow(dead_code)]
    pub async fn get_balance(&mut self, account_id: &str) -> Result<i64> {
        let request = GetBalanceRequest {
            account_id: account_id.to_string(),
        };
        let response = self.ledger.get_balance(request).await?;
        Ok(response.into_inner().balance)
    }

    #[allow(dead_code)]
    pub async fn credit(
        &mut self,
        account_id: &str,
        amount: i64,
        reference: &str,
    ) -> Result<Transaction> {
        let request = CreditRequest {
            account_id: account_id.to_string(),
            amount,
            reference: reference.to_string(),
        };
        let response = self.ledger.credit(request).await?;
        Ok(response.into_inner())
    }

    #[allow(dead_code)]
    pub async fn debit(
        &mut self,
        account_id: &str,
        amount: i64,
        reference: &str,
    ) -> Result<Transaction> {
        let request = DebitRequest {
            account_id: account_id.to_string(),
            amount,
            reference: reference.to_string(),
        };
        let response = self.ledger.debit(request).await?;
        Ok(response.into_inner())
    }

    pub async fn transfer(
        &mut self,
        entries: Vec<(String, i64)>,
        reference: &str,
    ) -> Result<Transaction> {
        let request = TransferRequest {
            entries: entries
                .into_iter()
                .map(|(account_id, amount)| TransferEntry { account_id, amount })
                .collect(),
            reference: reference.to_string(),
        };
        let response = self.ledger.transfer(request).await?;
        Ok(response.into_inner())
    }

    pub async fn list_transactions(
        &mut self,
        limit: Option<i32>,
        account_id: Option<&str>,
    ) -> Result<Vec<Transaction>> {
        let request = ListTransactionsRequest {
            limit: limit.unwrap_or(50),
            account_id: account_id.unwrap_or("").to_string(),
        };
        let response = self.ledger.list_transactions(request).await?;
        Ok(response.into_inner().transactions)
    }

    // Business operations

    #[allow(dead_code)]
    pub async fn purchase_invoice(
        &mut self,
        supplier_id: &str,
        buyer_id: &str,
        amount: i64,
        reference: &str,
    ) -> Result<BusinessTransactionResponse> {
        let request = PurchaseInvoiceRequest {
            supplier_id: supplier_id.to_string(),
            buyer_id: buyer_id.to_string(),
            amount,
            reference: reference.to_string(),
        };
        let response = self.business.purchase_invoice(request).await?;
        Ok(response.into_inner())
    }

    #[allow(dead_code)]
    pub async fn pay_invoice(
        &mut self,
        supplier_id: &str,
        buyer_id: &str,
        amount: i64,
        reference: &str,
    ) -> Result<BusinessTransactionResponse> {
        let request = PayInvoiceRequest {
            supplier_id: supplier_id.to_string(),
            buyer_id: buyer_id.to_string(),
            amount,
            reference: reference.to_string(),
        };
        let response = self.business.pay_invoice(request).await?;
        Ok(response.into_inner())
    }

    #[allow(dead_code)]
    pub async fn access_payment(
        &mut self,
        payer_id: &str,
        access_provider_id: &str,
        amount: i64,
        reference: &str,
        platform_id: Option<&str>,
        platform_fee: Option<i64>,
    ) -> Result<BusinessTransactionResponse> {
        let request = AccessPaymentRequest {
            payer_id: payer_id.to_string(),
            access_provider_id: access_provider_id.to_string(),
            amount,
            reference: reference.to_string(),
            platform_id: platform_id.unwrap_or("").to_string(),
            platform_fee: platform_fee.unwrap_or(0),
        };
        let response = self.business.access_payment(request).await?;
        Ok(response.into_inner())
    }
}

// Helper functions for display

pub fn role_to_string(role: i32) -> &'static str {
    match ParticipantRole::try_from(role) {
        Ok(ParticipantRole::AccessProvider) => "Access Provider",
        Ok(ParticipantRole::BankingPartner) => "Banking Partner",
        Ok(ParticipantRole::EcosystemPartner) => "Ecosystem Partner",
        Ok(ParticipantRole::Supplier) => "Supplier",
        Ok(ParticipantRole::EquipmentProvider) => "Equipment Provider",
        _ => "Unknown",
    }
}

pub fn account_type_to_string(account_type: i32) -> &'static str {
    match AccountType::try_from(account_type) {
        Ok(AccountType::Standalone) => "Standalone",
        Ok(AccountType::Operating) => "Operating",
        Ok(AccountType::Receivables) => "Receivables",
        Ok(AccountType::Payables) => "Payables",
        Ok(AccountType::Escrow) => "Escrow",
        Ok(AccountType::Fees) => "Fees",
        Ok(AccountType::Usage) => "Usage",
        _ => "Unknown",
    }
}

pub fn format_balance(balance: i64) -> String {
    let whole = balance / 100;
    let cents = (balance % 100).abs();
    if balance < 0 {
        format!("-{}.{:02}", whole.abs(), cents)
    } else {
        format!("{}.{:02}", whole, cents)
    }
}
