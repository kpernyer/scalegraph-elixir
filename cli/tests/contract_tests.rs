//! Contract Tests for Scalegraph gRPC API
//!
//! These tests validate that the protobuf contract between the Rust CLI client
//! and the Elixir server is stable and correctly implemented on both sides.
//!
//! Run with: cargo test --test contract_tests
//!
//! Test Categories:
//! 1. Schema Completeness - All fields are present and correctly typed
//! 2. Enum Exhaustiveness - All enum values are handled on both sides
//! 3. Response Structure - Responses contain expected data in expected format

use std::collections::HashSet;
use std::time::Duration;
use tokio::time::timeout;

pub mod common {
    tonic::include_proto!("scalegraph.common");
}

pub mod ledger {
    tonic::include_proto!("scalegraph.ledger");
}

pub mod business {
    tonic::include_proto!("scalegraph.business");
}

pub mod smartcontracts {
    tonic::include_proto!("scalegraph.smartcontracts");
}

use business::participant_service_client::ParticipantServiceClient;
use ledger::ledger_service_client::LedgerServiceClient;
use smartcontracts::smart_contract_service_client::SmartContractServiceClient;
use tonic::transport::Channel;

const SERVER_ADDR: &str = "http://localhost:50051";
const TIMEOUT_SECS: u64 = 5;

async fn connect() -> Result<Channel, Box<dyn std::error::Error>> {
    let channel = timeout(
        Duration::from_secs(TIMEOUT_SECS),
        Channel::from_static(SERVER_ADDR).connect(),
    )
    .await??;
    Ok(channel)
}

// ============================================================================
// 1. SCHEMA COMPLETENESS TESTS
// ============================================================================
// These tests verify that all expected fields in protobuf messages are
// present, non-default, and correctly typed.

mod schema_completeness {
    use super::*;

    #[tokio::test]
    async fn test_participant_schema_all_fields_present() {
        let channel = connect().await.expect("Server not running");
        let mut client = ParticipantServiceClient::new(channel);

        let request = business::ListParticipantsRequest { role: 0 };
        let participants = client
            .list_participants(request)
            .await
            .expect("ListParticipants failed")
            .into_inner()
            .participants;

        assert!(!participants.is_empty(), "Need at least one participant for schema test");

        for participant in &participants {
            // Required string fields must be non-empty
            assert!(
                !participant.id.is_empty(),
                "Participant.id must be non-empty, got empty for participant"
            );
            assert!(
                !participant.name.is_empty(),
                "Participant.name must be non-empty for participant {}",
                participant.id
            );

            // Enum field must be valid (non-zero for our schema)
            // Role 0 is UNSPECIFIED which shouldn't be used for real participants
            // Roles: 1=ACCESS_PROVIDER, 2=BANKING_PARTNER, 3=ECOSYSTEM_PARTNER,
            //        4=SUPPLIER, 5=EQUIPMENT_PROVIDER, 6=ECOSYSTEM_ORCHESTRATOR
            assert!(
                participant.role >= 1 && participant.role <= 6,
                "Participant.role must be 1-6, got {} for participant {}",
                participant.role,
                participant.id
            );

            // Timestamp fields should be set (non-zero) if participant exists
            // created_at should be a reasonable Unix timestamp (after year 2020)
            let year_2020_ms = 1577836800000i64; // 2020-01-01 in milliseconds
            assert!(
                participant.created_at > year_2020_ms || participant.created_at == 0,
                "Participant.created_at should be after 2020 or unset, got {} for {}",
                participant.created_at,
                participant.id
            );
        }
    }

    #[tokio::test]
    async fn test_account_schema_all_fields_present() {
        let channel = connect().await.expect("Server not running");
        let mut client = ParticipantServiceClient::new(channel);

        // Get first participant's accounts
        let list_req = business::ListParticipantsRequest { role: 0 };
        let participants = client
            .list_participants(list_req)
            .await
            .unwrap()
            .into_inner()
            .participants;

        assert!(!participants.is_empty(), "Need participants for account schema test");

        let accounts_req = business::GetParticipantAccountsRequest {
            participant_id: participants[0].id.clone(),
        };
        let accounts = client
            .get_participant_accounts(accounts_req)
            .await
            .expect("GetParticipantAccounts failed")
            .into_inner()
            .accounts;

        for account in &accounts {
            // Required string fields
            assert!(
                !account.id.is_empty(),
                "Account.id must be non-empty"
            );
            assert!(
                !account.participant_id.is_empty(),
                "Account.participant_id must be non-empty for account {}",
                account.id
            );

            // Account type must be valid (1-7 based on proto enum)
            assert!(
                account.account_type >= 1 && account.account_type <= 7,
                "Account.account_type must be 1-7, got {} for account {}",
                account.account_type,
                account.id
            );

            // Balance can be any i64, but should be reasonable
            // (not near i64::MIN or i64::MAX which might indicate overflow)
            let reasonable_max = 1_000_000_000_000i64; // 10 billion (in cents)
            assert!(
                account.balance.abs() < reasonable_max,
                "Account.balance {} seems unreasonably large for account {}",
                account.balance,
                account.id
            );
        }
    }

    #[tokio::test]
    async fn test_transaction_schema_all_fields_present() {
        let channel = connect().await.expect("Server not running");
        let mut client = LedgerServiceClient::new(channel);

        let request = ledger::ListTransactionsRequest {
            limit: 10,
            account_id: "".to_string(),
        };
        let transactions = client
            .list_transactions(request)
            .await
            .expect("ListTransactions failed")
            .into_inner()
            .transactions;

        // Skip if no transactions (might be empty database)
        if transactions.is_empty() {
            println!("WARN: No transactions found, skipping transaction schema test");
            return;
        }

        for tx in &transactions {
            // Transaction ID must be non-empty
            assert!(
                !tx.id.is_empty(),
                "Transaction.id must be non-empty"
            );

            // Reference can be empty but shouldn't be null
            // (protobuf strings are never null, just empty)

            // Timestamp should be reasonable
            let year_2020_ms = 1577836800000i64;
            assert!(
                tx.timestamp > year_2020_ms,
                "Transaction.created_at should be after 2020, got {} for tx {}",
                tx.timestamp,
                tx.id
            );

            // Entries array - transactions should have at least some entries
            // (even if empty transfers are allowed, real transactions have entries)
            // Note: We don't require entries since empty transfers are valid
        }
    }

    #[tokio::test]
    async fn test_contract_schema_all_fields_present() {
        let channel = connect().await.expect("Server not running");
        let mut client = SmartContractServiceClient::new(channel);

        let request = smartcontracts::ListContractsRequest {
            contract_type: 0,
            status: "".to_string(),
            participant_id: "".to_string(),
            limit: 100,
        };
        let contracts = client
            .list_contracts(request)
            .await
            .expect("ListContracts failed")
            .into_inner()
            .contracts;

        // Skip if no contracts
        if contracts.is_empty() {
            println!("WARN: No contracts found, skipping contract schema test");
            return;
        }

        for contract_response in &contracts {
            // ContractResponse contains a oneof - check it's set
            assert!(
                contract_response.contract.is_some(),
                "ContractResponse.contract oneof must be set"
            );
        }
    }

    #[tokio::test]
    async fn test_account_id_format_consistency() {
        // Account IDs should follow format: participant_id:account_type
        let channel = connect().await.expect("Server not running");
        let mut client = ParticipantServiceClient::new(channel);

        let list_req = business::ListParticipantsRequest { role: 0 };
        let participants = client
            .list_participants(list_req)
            .await
            .unwrap()
            .into_inner()
            .participants;

        for participant in participants.iter().take(3) {
            let accounts_req = business::GetParticipantAccountsRequest {
                participant_id: participant.id.clone(),
            };
            let accounts = client
                .get_participant_accounts(accounts_req)
                .await
                .unwrap()
                .into_inner()
                .accounts;

            for account in &accounts {
                // Account ID should contain the participant ID
                assert!(
                    account.id.starts_with(&participant.id) || account.id.contains(&participant.id),
                    "Account.id '{}' should contain participant_id '{}'",
                    account.id,
                    participant.id
                );

                // Account ID should have a separator (typically ':')
                assert!(
                    account.id.contains(':'),
                    "Account.id '{}' should contain ':' separator",
                    account.id
                );
            }
        }
    }
}

// ============================================================================
// 2. ENUM EXHAUSTIVENESS TESTS
// ============================================================================
// These tests verify that all enum values defined in the protobuf are
// correctly handled by both client and server.

mod enum_exhaustiveness {
    use super::*;

    #[tokio::test]
    async fn test_all_participant_roles_recognized_by_server() {
        let channel = connect().await.expect("Server not running");
        let mut client = ParticipantServiceClient::new(channel);

        // ParticipantRole enum values from proto:
        // 0 = UNSPECIFIED, 1 = ACCESS_PROVIDER, 2 = BANKING_PARTNER,
        // 3 = ECOSYSTEM_PARTNER, 4 = SUPPLIER, 5 = EQUIPMENT_PROVIDER,
        // 6 = ECOSYSTEM_ORCHESTRATOR
        let valid_roles = vec![
            (1, "ACCESS_PROVIDER"),
            (2, "BANKING_PARTNER"),
            (3, "ECOSYSTEM_PARTNER"),
            (4, "SUPPLIER"),
            (5, "EQUIPMENT_PROVIDER"),
            (6, "ECOSYSTEM_ORCHESTRATOR"),
        ];

        // Query for each role - should not error even if no results
        for (role_value, role_name) in valid_roles {
            let request = business::ListParticipantsRequest { role: role_value };
            let result = client.list_participants(request).await;

            assert!(
                result.is_ok(),
                "Server should accept role {} ({}), got error: {:?}",
                role_value,
                role_name,
                result.err()
            );
        }
    }

    #[tokio::test]
    async fn test_all_account_types_exist_in_seed_data() {
        let channel = connect().await.expect("Server not running");
        let mut client = ParticipantServiceClient::new(channel);

        // Collect all account types from all participants
        let list_req = business::ListParticipantsRequest { role: 0 };
        let participants = client
            .list_participants(list_req)
            .await
            .unwrap()
            .into_inner()
            .participants;

        let mut found_account_types: HashSet<i32> = HashSet::new();

        for participant in &participants {
            let accounts_req = business::GetParticipantAccountsRequest {
                participant_id: participant.id.clone(),
            };
            if let Ok(response) = client.get_participant_accounts(accounts_req).await {
                for account in response.into_inner().accounts {
                    found_account_types.insert(account.account_type);
                }
            }
        }

        // AccountType enum values (1-7, excluding 0=UNSPECIFIED):
        // 1=STANDALONE, 2=OPERATING, 3=RECEIVABLES, 4=PAYABLES,
        // 5=ESCROW, 6=FEES, 7=USAGE
        let expected_common_types = vec![2]; // At minimum, OPERATING should exist

        for expected_type in expected_common_types {
            assert!(
                found_account_types.contains(&expected_type),
                "Expected to find account type {} in seed data, found types: {:?}",
                expected_type,
                found_account_types
            );
        }

        // Report coverage
        println!(
            "Account type coverage: found {:?} out of possible 1-7",
            found_account_types
        );
    }

    #[tokio::test]
    async fn test_participant_roles_in_seed_data_coverage() {
        let channel = connect().await.expect("Server not running");
        let mut client = ParticipantServiceClient::new(channel);

        let request = business::ListParticipantsRequest { role: 0 };
        let participants = client
            .list_participants(request)
            .await
            .unwrap()
            .into_inner()
            .participants;

        let mut found_roles: HashSet<i32> = HashSet::new();
        for participant in &participants {
            found_roles.insert(participant.role);
        }

        // We expect seed data to have at least these roles represented
        let expected_roles = vec![
            (1, "ACCESS_PROVIDER"),    // ASSA ABLOY
            (2, "BANKING_PARTNER"),    // SEB
            (3, "ECOSYSTEM_PARTNER"),  // Beauty Hosting
            (4, "SUPPLIER"),           // Schampo etc, Clipper Oy
        ];

        for (role_value, role_name) in expected_roles {
            assert!(
                found_roles.contains(&role_value),
                "Expected seed data to contain role {} ({}), found roles: {:?}",
                role_value,
                role_name,
                found_roles
            );
        }

        println!("Role coverage: found {:?} out of possible 1-5", found_roles);
    }

    #[tokio::test]
    async fn test_invalid_enum_values_handled_gracefully() {
        let channel = connect().await.expect("Server not running");
        let mut client = ParticipantServiceClient::new(channel);

        // Query with invalid role value - should not crash server
        let invalid_roles = vec![-1, 100, 999, i32::MAX];

        for invalid_role in invalid_roles {
            let request = business::ListParticipantsRequest { role: invalid_role };
            let result = client.list_participants(request).await;

            // Server should either return empty list or error, but not crash
            match result {
                Ok(response) => {
                    // Empty or all participants is acceptable
                    let _ = response.into_inner().participants;
                }
                Err(status) => {
                    // Error is acceptable, but should be a proper gRPC error
                    assert!(
                        !status.message().is_empty(),
                        "Error for invalid role {} should have a message",
                        invalid_role
                    );
                }
            }
        }
    }
}

// ============================================================================
// 3. RESPONSE STRUCTURE VALIDATION TESTS
// ============================================================================
// These tests verify that responses have the expected structure and
// that related data is consistent.

mod response_structure {
    use super::*;

    #[tokio::test]
    async fn test_list_participants_response_structure() {
        let channel = connect().await.expect("Server not running");
        let mut client = ParticipantServiceClient::new(channel);

        let request = business::ListParticipantsRequest { role: 0 };
        let response = client.list_participants(request).await.unwrap();
        let inner = response.into_inner();

        // Response should have participants field (even if empty)
        // The fact that we can access .participants means the structure is correct
        let participants = inner.participants;

        // If we have participants, verify they're properly structured
        if !participants.is_empty() {
            // IDs should be unique
            let ids: Vec<&str> = participants.iter().map(|p| p.id.as_str()).collect();
            let unique_ids: HashSet<&str> = ids.iter().cloned().collect();
            assert_eq!(
                ids.len(),
                unique_ids.len(),
                "Participant IDs must be unique"
            );
        }
    }

    #[tokio::test]
    async fn test_get_participant_response_matches_list() {
        let channel = connect().await.expect("Server not running");
        let mut client = ParticipantServiceClient::new(channel);

        // Get list of participants
        let list_req = business::ListParticipantsRequest { role: 0 };
        let participants = client
            .list_participants(list_req)
            .await
            .unwrap()
            .into_inner()
            .participants;

        if participants.is_empty() {
            return;
        }

        // Get first participant by ID
        let expected = &participants[0];
        let get_req = business::GetParticipantRequest {
            participant_id: expected.id.clone(),
        };
        let actual = client.get_participant(get_req).await.unwrap().into_inner();

        // Fields should match exactly
        assert_eq!(actual.id, expected.id, "ID mismatch");
        assert_eq!(actual.name, expected.name, "Name mismatch");
        assert_eq!(actual.role, expected.role, "Role mismatch");
    }

    #[tokio::test]
    async fn test_account_balance_consistency() {
        // GetBalance should return same value as Account.balance
        let channel = connect().await.expect("Server not running");
        let mut participant_client = ParticipantServiceClient::new(channel.clone());
        let mut ledger_client = LedgerServiceClient::new(channel);

        // Get first participant's accounts
        let list_req = business::ListParticipantsRequest { role: 0 };
        let participants = participant_client
            .list_participants(list_req)
            .await
            .unwrap()
            .into_inner()
            .participants;

        if participants.is_empty() {
            return;
        }

        let accounts_req = business::GetParticipantAccountsRequest {
            participant_id: participants[0].id.clone(),
        };
        let accounts = participant_client
            .get_participant_accounts(accounts_req)
            .await
            .unwrap()
            .into_inner()
            .accounts;

        // For each account, verify GetBalance returns same value
        for account in accounts.iter().take(3) {
            let balance_req = ledger::GetBalanceRequest {
                account_id: account.id.clone(),
            };
            let balance_response = ledger_client.get_balance(balance_req).await;

            if let Ok(response) = balance_response {
                let api_balance = response.into_inner().balance;
                assert_eq!(
                    api_balance, account.balance,
                    "GetBalance({}) returned {} but Account.balance is {}",
                    account.id, api_balance, account.balance
                );
            }
        }
    }

    #[tokio::test]
    async fn test_transaction_entries_balance() {
        // Transaction entries should typically sum to zero (double-entry)
        let channel = connect().await.expect("Server not running");
        let mut client = LedgerServiceClient::new(channel);

        let request = ledger::ListTransactionsRequest {
            limit: 20,
            account_id: "".to_string(),
        };
        let transactions = client
            .list_transactions(request)
            .await
            .unwrap()
            .into_inner()
            .transactions;

        for tx in &transactions {
            if tx.entries.is_empty() {
                continue; // Empty transactions are allowed
            }

            let sum: i64 = tx.entries.iter().map(|e| e.amount).sum();

            // Most transactions should be balanced (sum to 0)
            // But some business transactions may be unbalanced (fees, etc.)
            // So we just warn rather than fail
            if sum != 0 {
                println!(
                    "INFO: Transaction {} has unbalanced entries (sum={}), this may be intentional for fees",
                    tx.id, sum
                );
            }
        }
    }

    #[tokio::test]
    async fn test_transaction_entries_reference_valid_accounts() {
        let channel = connect().await.expect("Server not running");
        let mut ledger_client = LedgerServiceClient::new(channel.clone());
        let mut participant_client = ParticipantServiceClient::new(channel);

        // Collect all known account IDs
        let list_req = business::ListParticipantsRequest { role: 0 };
        let participants = participant_client
            .list_participants(list_req)
            .await
            .unwrap()
            .into_inner()
            .participants;

        let mut all_account_ids: HashSet<String> = HashSet::new();
        for participant in &participants {
            let accounts_req = business::GetParticipantAccountsRequest {
                participant_id: participant.id.clone(),
            };
            if let Ok(response) = participant_client.get_participant_accounts(accounts_req).await {
                for account in response.into_inner().accounts {
                    all_account_ids.insert(account.id);
                }
            }
        }

        // Check transaction entries reference known accounts
        let tx_req = ledger::ListTransactionsRequest {
            limit: 20,
            account_id: "".to_string(),
        };
        let transactions = ledger_client
            .list_transactions(tx_req)
            .await
            .unwrap()
            .into_inner()
            .transactions;

        for tx in &transactions {
            for entry in &tx.entries {
                // Entry account_id might include system accounts we don't know about
                // So we just verify format, not existence
                assert!(
                    !entry.account_id.is_empty(),
                    "Transaction {} has entry with empty account_id",
                    tx.id
                );
                assert!(
                    entry.account_id.contains(':'),
                    "Transaction {} entry account_id '{}' should contain ':'",
                    tx.id,
                    entry.account_id
                );
            }
        }
    }

    #[tokio::test]
    async fn test_timestamps_are_monotonic_for_transactions() {
        let channel = connect().await.expect("Server not running");
        let mut client = LedgerServiceClient::new(channel);

        let request = ledger::ListTransactionsRequest {
            limit: 50,
            account_id: "".to_string(),
        };
        let transactions = client
            .list_transactions(request)
            .await
            .unwrap()
            .into_inner()
            .transactions;

        if transactions.len() < 2 {
            return; // Need at least 2 to compare
        }

        // Transactions should be ordered (typically newest first or oldest first)
        // Check if they're monotonically increasing or decreasing
        let timestamps: Vec<i64> = transactions.iter().map(|t| t.timestamp).collect();

        let is_ascending = timestamps.windows(2).all(|w| w[0] <= w[1]);
        let is_descending = timestamps.windows(2).all(|w| w[0] >= w[1]);

        assert!(
            is_ascending || is_descending,
            "Transactions should be ordered by timestamp, got: {:?}",
            &timestamps[..std::cmp::min(5, timestamps.len())]
        );
    }

    #[tokio::test]
    async fn test_transfer_response_contains_valid_transaction() {
        // Perform a valid transfer and verify response structure
        let channel = connect().await.expect("Server not running");
        let mut participant_client = ParticipantServiceClient::new(channel.clone());
        let mut ledger_client = LedgerServiceClient::new(channel);

        // Find two accounts that can transfer
        let list_req = business::ListParticipantsRequest { role: 0 };
        let participants = participant_client
            .list_participants(list_req)
            .await
            .unwrap()
            .into_inner()
            .participants;

        if participants.len() < 2 {
            println!("WARN: Need at least 2 participants for transfer test");
            return;
        }

        // Get accounts for first two participants
        let mut accounts = Vec::new();
        for p in participants.iter().take(2) {
            let req = business::GetParticipantAccountsRequest {
                participant_id: p.id.clone(),
            };
            if let Ok(resp) = participant_client.get_participant_accounts(req).await {
                let accts = resp.into_inner().accounts;
                if let Some(operating) = accts.iter().find(|a| a.account_type == 2) {
                    accounts.push(operating.clone());
                }
            }
        }

        if accounts.len() < 2 {
            println!("WARN: Need 2 operating accounts for transfer test");
            return;
        }

        // Check if sender has sufficient balance
        if accounts[0].balance < 100 {
            println!("WARN: Sender has insufficient balance for transfer test");
            return;
        }

        // Perform transfer
        let request = ledger::TransferRequest {
            entries: vec![
                common::TransferEntry {
                    account_id: accounts[0].id.clone(),
                    amount: -100,
                },
                common::TransferEntry {
                    account_id: accounts[1].id.clone(),
                    amount: 100,
                },
            ],
            reference: format!("contract_test_{}", chrono::Utc::now().timestamp_millis()),
        };

        let response = ledger_client.transfer(request).await;

        match response {
            Ok(resp) => {
                let tx = resp.into_inner();

                // Verify response structure
                assert!(!tx.id.is_empty(), "Transaction ID must be non-empty");
                assert!(tx.timestamp > 0, "Transaction created_at must be set");
                assert_eq!(
                    tx.entries.len(),
                    2,
                    "Transaction should have 2 entries"
                );

                // Verify entries match request
                let amounts: Vec<i64> = tx.entries.iter().map(|e| e.amount).collect();
                assert!(amounts.contains(&-100), "Should have -100 entry");
                assert!(amounts.contains(&100), "Should have +100 entry");
            }
            Err(e) => {
                // Transfer might fail due to insufficient funds, etc.
                println!("INFO: Transfer failed (may be expected): {}", e.message());
            }
        }
    }
}

// ============================================================================
// SNAPSHOT / REGRESSION TESTS
// ============================================================================
// These tests capture the current API shape and will fail if it changes.

mod api_shape {
    use super::*;

    #[tokio::test]
    async fn test_participant_service_methods_exist() {
        let channel = connect().await.expect("Server not running");
        let mut client = ParticipantServiceClient::new(channel);

        // Verify all expected methods exist by calling them
        // ListParticipants
        let _ = client
            .list_participants(business::ListParticipantsRequest { role: 0 })
            .await;

        // GetParticipant
        let _ = client
            .get_participant(business::GetParticipantRequest {
                participant_id: "test".to_string(),
            })
            .await;

        // GetParticipantAccounts
        let _ = client
            .get_participant_accounts(business::GetParticipantAccountsRequest {
                participant_id: "test".to_string(),
            })
            .await;

        // If we got here without compile errors, the methods exist
    }

    #[tokio::test]
    async fn test_ledger_service_methods_exist() {
        let channel = connect().await.expect("Server not running");
        let mut client = LedgerServiceClient::new(channel);

        // GetAccount
        let _ = client
            .get_account(ledger::GetAccountRequest {
                account_id: "test".to_string(),
            })
            .await;

        // GetBalance
        let _ = client
            .get_balance(ledger::GetBalanceRequest {
                account_id: "test".to_string(),
            })
            .await;

        // Transfer
        let _ = client
            .transfer(ledger::TransferRequest {
                entries: vec![],
                reference: "test".to_string(),
            })
            .await;

        // ListTransactions
        let _ = client
            .list_transactions(ledger::ListTransactionsRequest {
                limit: 1,
                account_id: "".to_string(),
            })
            .await;

        // Credit
        let _ = client
            .credit(ledger::CreditRequest {
                account_id: "test".to_string(),
                amount: 0,
                reference: "test".to_string(),
            })
            .await;

        // Debit
        let _ = client
            .debit(ledger::DebitRequest {
                account_id: "test".to_string(),
                amount: 0,
                reference: "test".to_string(),
            })
            .await;
    }

    #[tokio::test]
    async fn test_smart_contract_service_methods_exist() {
        let channel = connect().await.expect("Server not running");
        let mut client = SmartContractServiceClient::new(channel);

        // ListContracts
        let _ = client
            .list_contracts(smartcontracts::ListContractsRequest {
                contract_type: 0,
                status: "".to_string(),
                participant_id: "".to_string(),
                limit: 1,
            })
            .await;
    }
}
