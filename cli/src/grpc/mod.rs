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
use common::{Account, AccountType, Participant, ParticipantRole, Transaction, TransferEntry};
use ledger::{
    ledger_service_client::LedgerServiceClient, CreditRequest, DebitRequest, GetAccountRequest,
    GetBalanceRequest, ListTransactionsRequest, TransferRequest,
};
use business::{
    business_service_client::BusinessServiceClient, participant_service_client::ParticipantServiceClient,
    AccessPaymentRequest, BusinessTransactionResponse, GetParticipantAccountsRequest,
    GetParticipantRequest, ListParticipantsRequest, PayInvoiceRequest, PurchaseInvoiceRequest,
};
use smartcontracts::{
    smart_contract_service_client::SmartContractServiceClient, ContractResponse,
    CreateGenericContractRequest, GenericContract, ListContractsRequest,
};
use tonic::transport::Channel;

#[derive(Clone)]
pub struct ScalegraphClient {
    ledger: LedgerServiceClient<Channel>,
    participant: ParticipantServiceClient<Channel>,
    business: BusinessServiceClient<Channel>,
    contracts: SmartContractServiceClient<Channel>,
}

impl ScalegraphClient {
    pub async fn connect(addr: &str) -> Result<Self> {
        let channel = Channel::from_shared(addr.to_string())?.connect().await?;

        Ok(Self {
            ledger: LedgerServiceClient::new(channel.clone()),
            participant: ParticipantServiceClient::new(channel.clone()),
            business: BusinessServiceClient::new(channel.clone()),
            contracts: SmartContractServiceClient::new(channel),
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

    // Smart contract operations

    pub async fn list_contracts(
        &mut self,
        contract_type: Option<i32>,
        status: Option<String>,
        participant_id: Option<String>,
        limit: Option<i32>,
    ) -> Result<Vec<ContractResponse>> {
        let request = ListContractsRequest {
            contract_type: contract_type.unwrap_or(0),
            status: status.unwrap_or_default(),
            participant_id: participant_id.unwrap_or_default(),
            limit: limit.unwrap_or(100),
        };
        let response = self.contracts.list_contracts(request).await?;
        Ok(response.into_inner().contracts)
    }

    pub async fn create_generic_contract(
        &mut self,
        yaml_content: &str,
        variables: &std::collections::HashMap<String, String>,
    ) -> Result<GenericContract> {
        let request = CreateGenericContractRequest {
            yaml_content: yaml_content.to_string(),
            yaml_file_path: String::new(),
            variables: variables.clone(),
        };
        let response = self.contracts.create_generic_contract(request).await?;
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
        Ok(ParticipantRole::EcosystemOrchestrator) => "Ecosystem Orchestrator",
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

#[cfg(test)]
mod tests {
    use super::*;

    // ============================================================================
    // UNIT TESTS - format_balance
    // ============================================================================

    #[test]
    fn test_format_balance_zero() {
        assert_eq!(format_balance(0), "0.00");
    }

    #[test]
    fn test_format_balance_positive_whole() {
        assert_eq!(format_balance(100), "1.00");
        assert_eq!(format_balance(500), "5.00");
        assert_eq!(format_balance(10000), "100.00");
    }

    #[test]
    fn test_format_balance_positive_with_cents() {
        assert_eq!(format_balance(101), "1.01");
        assert_eq!(format_balance(199), "1.99");
        assert_eq!(format_balance(1234), "12.34");
        assert_eq!(format_balance(12345), "123.45");
    }

    #[test]
    fn test_format_balance_negative_whole() {
        assert_eq!(format_balance(-100), "-1.00");
        assert_eq!(format_balance(-500), "-5.00");
        assert_eq!(format_balance(-10000), "-100.00");
    }

    #[test]
    fn test_format_balance_negative_with_cents() {
        assert_eq!(format_balance(-101), "-1.01");
        assert_eq!(format_balance(-199), "-1.99");
        assert_eq!(format_balance(-1234), "-12.34");
    }

    #[test]
    fn test_format_balance_only_cents() {
        assert_eq!(format_balance(1), "0.01");
        assert_eq!(format_balance(50), "0.50");
        assert_eq!(format_balance(99), "0.99");
    }

    #[test]
    fn test_format_balance_negative_only_cents() {
        assert_eq!(format_balance(-1), "-0.01");
        assert_eq!(format_balance(-50), "-0.50");
        assert_eq!(format_balance(-99), "-0.99");
    }

    // ============================================================================
    // UNIT TESTS - role_to_string
    // ============================================================================

    #[test]
    fn test_role_to_string_access_provider() {
        assert_eq!(role_to_string(1), "Access Provider");
    }

    #[test]
    fn test_role_to_string_banking_partner() {
        assert_eq!(role_to_string(2), "Banking Partner");
    }

    #[test]
    fn test_role_to_string_ecosystem_partner() {
        assert_eq!(role_to_string(3), "Ecosystem Partner");
    }

    #[test]
    fn test_role_to_string_supplier() {
        assert_eq!(role_to_string(4), "Supplier");
    }

    #[test]
    fn test_role_to_string_equipment_provider() {
        assert_eq!(role_to_string(5), "Equipment Provider");
    }

    #[test]
    fn test_role_to_string_ecosystem_orchestrator() {
        assert_eq!(role_to_string(6), "Ecosystem Orchestrator");
    }

    // ============================================================================
    // UNIT TESTS - account_type_to_string
    // ============================================================================
    // Note: Enum values match protobuf definition in proto/common.proto
    // 0 = UNSPECIFIED, 1 = STANDALONE, 2 = OPERATING, etc.

    #[test]
    fn test_account_type_unspecified() {
        assert_eq!(account_type_to_string(0), "Unknown");
    }

    #[test]
    fn test_account_type_standalone() {
        assert_eq!(account_type_to_string(1), "Standalone");
    }

    #[test]
    fn test_account_type_operating() {
        assert_eq!(account_type_to_string(2), "Operating");
    }

    #[test]
    fn test_account_type_receivables() {
        assert_eq!(account_type_to_string(3), "Receivables");
    }

    #[test]
    fn test_account_type_payables() {
        assert_eq!(account_type_to_string(4), "Payables");
    }

    #[test]
    fn test_account_type_escrow() {
        assert_eq!(account_type_to_string(5), "Escrow");
    }

    #[test]
    fn test_account_type_fees() {
        assert_eq!(account_type_to_string(6), "Fees");
    }

    #[test]
    fn test_account_type_usage() {
        assert_eq!(account_type_to_string(7), "Usage");
    }

    // ============================================================================
    // NEGATIVE TESTS - Invalid inputs and edge cases
    // ============================================================================

    #[test]
    fn test_role_to_string_invalid_zero() {
        // 0 is not a valid role, should return "Unknown"
        assert_eq!(role_to_string(0), "Unknown");
    }

    #[test]
    fn test_role_to_string_invalid_negative() {
        assert_eq!(role_to_string(-1), "Unknown");
        assert_eq!(role_to_string(-100), "Unknown");
    }

    #[test]
    fn test_role_to_string_invalid_too_high() {
        assert_eq!(role_to_string(7), "Unknown");
        assert_eq!(role_to_string(100), "Unknown");
        assert_eq!(role_to_string(i32::MAX), "Unknown");
    }

    #[test]
    fn test_account_type_invalid_negative() {
        assert_eq!(account_type_to_string(-1), "Unknown");
        assert_eq!(account_type_to_string(-100), "Unknown");
    }

    #[test]
    fn test_account_type_invalid_too_high() {
        assert_eq!(account_type_to_string(8), "Unknown");
        assert_eq!(account_type_to_string(100), "Unknown");
        assert_eq!(account_type_to_string(i32::MAX), "Unknown");
    }

    #[test]
    fn test_format_balance_large_positive() {
        // Test very large balances (millions)
        assert_eq!(format_balance(100_000_000), "1000000.00");
        assert_eq!(format_balance(999_999_999), "9999999.99");
    }

    #[test]
    fn test_format_balance_large_negative() {
        assert_eq!(format_balance(-100_000_000), "-1000000.00");
        assert_eq!(format_balance(-999_999_999), "-9999999.99");
    }

    #[test]
    fn test_format_balance_i64_boundaries() {
        // Test near i64 boundaries (avoid actual boundaries due to division)
        let large = i64::MAX / 100;
        let result = format_balance(large * 100);
        assert!(result.ends_with(".00"));

        let large_neg = i64::MIN / 100;
        let result_neg = format_balance(large_neg * 100);
        assert!(result_neg.starts_with("-"));
    }

    // ============================================================================
    // PROPERTY TESTS
    // ============================================================================

    mod property_tests {
        use super::*;
        use proptest::prelude::*;

        proptest! {
            // Property: format_balance output always contains exactly one decimal point
            #[test]
            fn format_balance_has_decimal_point(balance in any::<i64>()) {
                let result = format_balance(balance);
                let decimal_count = result.matches('.').count();
                prop_assert_eq!(decimal_count, 1, "Expected exactly one decimal point in '{}'", result);
            }

            // Property: format_balance output always has exactly 2 digits after decimal
            #[test]
            fn format_balance_has_two_decimal_places(balance in any::<i64>()) {
                let result = format_balance(balance);
                let parts: Vec<&str> = result.split('.').collect();
                prop_assert_eq!(parts.len(), 2, "Expected format 'X.XX' but got '{}'", result);
                prop_assert_eq!(parts[1].len(), 2, "Expected 2 decimal places but got {} in '{}'", parts[1].len(), result);
            }

            // Property: negative balances start with '-'
            #[test]
            fn negative_balance_starts_with_minus(balance in i64::MIN..0i64) {
                let result = format_balance(balance);
                prop_assert!(result.starts_with('-'), "Expected '-' prefix for negative balance {} but got '{}'", balance, result);
            }

            // Property: non-negative balances don't start with '-'
            #[test]
            fn non_negative_balance_no_minus(balance in 0i64..=i64::MAX) {
                let result = format_balance(balance);
                prop_assert!(!result.starts_with('-'), "Expected no '-' prefix for balance {} but got '{}'", balance, result);
            }

            // Property: format_balance is deterministic
            #[test]
            fn format_balance_is_deterministic(balance in any::<i64>()) {
                let result1 = format_balance(balance);
                let result2 = format_balance(balance);
                prop_assert_eq!(result1, result2, "Expected deterministic output for {}", balance);
            }

            // Property: valid role values (1-6) never return "Unknown"
            #[test]
            fn valid_roles_return_known_string(role in 1i32..=6) {
                let result = role_to_string(role);
                prop_assert_ne!(result, "Unknown", "Role {} should not be Unknown", role);
            }

            // Property: invalid role values return "Unknown"
            #[test]
            fn invalid_roles_return_unknown(role in prop::num::i32::ANY.prop_filter("not valid role", |r| *r < 1 || *r > 6)) {
                let result = role_to_string(role);
                prop_assert_eq!(result, "Unknown", "Role {} should be Unknown but got '{}'", role, result);
            }

            // Property: valid account types (1-7) never return "Unknown"
            // Note: 0 is UNSPECIFIED which maps to "Unknown"
            #[test]
            fn valid_account_types_return_known_string(account_type in 1i32..=7) {
                let result = account_type_to_string(account_type);
                prop_assert_ne!(result, "Unknown", "Account type {} should not be Unknown", account_type);
            }

            // Property: invalid account types return "Unknown"
            #[test]
            fn invalid_account_types_return_unknown(account_type in prop::num::i32::ANY.prop_filter("not valid type", |t| *t < 1 || *t > 7)) {
                let result = account_type_to_string(account_type);
                prop_assert_eq!(result, "Unknown", "Account type {} should be Unknown but got '{}'", account_type, result);
            }

            // Property: balance in cents equals parsed output * 100 (for reasonable values)
            // Limited to avoid floating point precision issues with very large numbers
            #[test]
            fn format_balance_roundtrip(balance in 0i64..=999_999_999_99i64) {
                let cents = balance;
                let result = format_balance(cents);
                // Parse back: parse as f64, multiply by 100
                let parsed: f64 = result.parse().unwrap();
                let recovered = (parsed * 100.0).round() as i64;
                prop_assert_eq!(cents, recovered, "Roundtrip failed: {} -> '{}' -> {}", cents, result, recovered);
            }
        }
    }
}
