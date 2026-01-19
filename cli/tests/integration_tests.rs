//! Integration tests for Scalegraph CLI
//!
//! These tests require a running Scalegraph server on localhost:50051.
//! Run with: cargo test --test integration_tests
//!
//! To skip these tests when server is not running:
//!   cargo test --lib  (runs only unit tests)

use std::time::Duration;
use tokio::time::timeout;

// Import the gRPC client module from the main crate
// We need to rebuild the proto in tests context
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

/// Helper to connect to the server with timeout
async fn connect() -> Result<Channel, Box<dyn std::error::Error>> {
    let channel = timeout(
        Duration::from_secs(TIMEOUT_SECS),
        Channel::from_static(SERVER_ADDR).connect(),
    )
    .await??;
    Ok(channel)
}

// ============================================================================
// CONNECTION TESTS
// ============================================================================

#[tokio::test]
async fn test_server_connection() {
    let result = connect().await;
    assert!(
        result.is_ok(),
        "Failed to connect to server at {}. Is it running?",
        SERVER_ADDR
    );
}

// ============================================================================
// PARTICIPANT SERVICE TESTS
// ============================================================================

#[tokio::test]
async fn test_list_participants_returns_results() {
    let channel = connect().await.expect("Server not running");
    let mut client = ParticipantServiceClient::new(channel);

    let request = business::ListParticipantsRequest { role: 0 };
    let response = client.list_participants(request).await;

    assert!(response.is_ok(), "ListParticipants failed: {:?}", response.err());
    let participants = response.unwrap().into_inner().participants;
    assert!(!participants.is_empty(), "Expected at least one participant");
}

#[tokio::test]
async fn test_list_participants_contains_expected_names() {
    let channel = connect().await.expect("Server not running");
    let mut client = ParticipantServiceClient::new(channel);

    let request = business::ListParticipantsRequest { role: 0 };
    let response = client.list_participants(request).await.unwrap();
    let participants = response.into_inner().participants;

    let names: Vec<&str> = participants.iter().map(|p| p.name.as_str()).collect();

    // Check for expected seed data participants
    assert!(
        names.iter().any(|n| n.contains("ASSA") || n.contains("SEB") || n.contains("Beauty")),
        "Expected to find seed participants, got: {:?}",
        names
    );
}

#[tokio::test]
async fn test_get_participant_accounts() {
    let channel = connect().await.expect("Server not running");
    let mut client = ParticipantServiceClient::new(channel);

    // First get a participant ID
    let list_req = business::ListParticipantsRequest { role: 0 };
    let participants = client
        .list_participants(list_req)
        .await
        .unwrap()
        .into_inner()
        .participants;

    assert!(!participants.is_empty(), "No participants found");
    let participant_id = &participants[0].id;

    // Now get their accounts
    let accounts_req = business::GetParticipantAccountsRequest {
        participant_id: participant_id.clone(),
    };
    let response = client.get_participant_accounts(accounts_req).await;

    assert!(
        response.is_ok(),
        "GetParticipantAccounts failed: {:?}",
        response.err()
    );
}

#[tokio::test]
async fn test_get_participant_by_id() {
    let channel = connect().await.expect("Server not running");
    let mut client = ParticipantServiceClient::new(channel);

    // First get a participant ID
    let list_req = business::ListParticipantsRequest { role: 0 };
    let participants = client
        .list_participants(list_req)
        .await
        .unwrap()
        .into_inner()
        .participants;

    let participant_id = &participants[0].id;

    // Get specific participant
    let get_req = business::GetParticipantRequest {
        participant_id: participant_id.clone(),
    };
    let response = client.get_participant(get_req).await;

    assert!(response.is_ok(), "GetParticipant failed: {:?}", response.err());
    let participant = response.unwrap().into_inner();
    assert_eq!(&participant.id, participant_id);
}

// ============================================================================
// NEGATIVE TESTS - PARTICIPANT SERVICE
// ============================================================================

#[tokio::test]
async fn test_get_nonexistent_participant_fails() {
    let channel = connect().await.expect("Server not running");
    let mut client = ParticipantServiceClient::new(channel);

    let request = business::GetParticipantRequest {
        participant_id: "nonexistent_participant_12345".to_string(),
    };
    let response = client.get_participant(request).await;

    assert!(
        response.is_err(),
        "Expected error for nonexistent participant"
    );
}

#[tokio::test]
async fn test_get_accounts_for_nonexistent_participant() {
    let channel = connect().await.expect("Server not running");
    let mut client = ParticipantServiceClient::new(channel);

    let request = business::GetParticipantAccountsRequest {
        participant_id: "nonexistent_participant_12345".to_string(),
    };
    let response = client.get_participant_accounts(request).await;

    // Should either error or return empty list
    match response {
        Ok(resp) => {
            let accounts = resp.into_inner().accounts;
            assert!(accounts.is_empty(), "Expected no accounts for nonexistent participant");
        }
        Err(_) => {
            // Error is also acceptable
        }
    }
}

// ============================================================================
// LEDGER SERVICE TESTS
// ============================================================================

#[tokio::test]
async fn test_list_transactions() {
    let channel = connect().await.expect("Server not running");
    let mut client = LedgerServiceClient::new(channel);

    let request = ledger::ListTransactionsRequest {
        limit: 10,
        account_id: "".to_string(),
    };
    let response = client.list_transactions(request).await;

    assert!(
        response.is_ok(),
        "ListTransactions failed: {:?}",
        response.err()
    );
}

#[tokio::test]
async fn test_get_balance_for_valid_account() {
    // First we need to find a valid account ID
    let channel = connect().await.expect("Server not running");
    let mut participant_client = ParticipantServiceClient::new(channel.clone());

    // Get first participant
    let list_req = business::ListParticipantsRequest { role: 0 };
    let participants = participant_client
        .list_participants(list_req)
        .await
        .unwrap()
        .into_inner()
        .participants;

    if participants.is_empty() {
        return; // Skip if no participants
    }

    // Get their accounts
    let accounts_req = business::GetParticipantAccountsRequest {
        participant_id: participants[0].id.clone(),
    };
    let accounts = participant_client
        .get_participant_accounts(accounts_req)
        .await
        .unwrap()
        .into_inner()
        .accounts;

    if accounts.is_empty() {
        return; // Skip if no accounts
    }

    // Now test GetBalance
    let mut ledger_client = LedgerServiceClient::new(channel);
    let balance_req = ledger::GetBalanceRequest {
        account_id: accounts[0].id.clone(),
    };
    let response = ledger_client.get_balance(balance_req).await;

    assert!(response.is_ok(), "GetBalance failed: {:?}", response.err());
}

// ============================================================================
// NEGATIVE TESTS - LEDGER SERVICE
// ============================================================================

#[tokio::test]
async fn test_get_balance_nonexistent_account() {
    let channel = connect().await.expect("Server not running");
    let mut client = LedgerServiceClient::new(channel);

    let request = ledger::GetBalanceRequest {
        account_id: "nonexistent:operating".to_string(),
    };
    let response = client.get_balance(request).await;

    assert!(
        response.is_err(),
        "Expected error for nonexistent account"
    );
}

#[tokio::test]
async fn test_get_account_nonexistent() {
    let channel = connect().await.expect("Server not running");
    let mut client = LedgerServiceClient::new(channel);

    let request = ledger::GetAccountRequest {
        account_id: "totally_fake_account_xyz".to_string(),
    };
    let response = client.get_account(request).await;

    assert!(response.is_err(), "Expected error for nonexistent account");
}

// ============================================================================
// SMART CONTRACT SERVICE TESTS
// ============================================================================

#[tokio::test]
async fn test_list_contracts() {
    let channel = connect().await.expect("Server not running");
    let mut client = SmartContractServiceClient::new(channel);

    let request = smartcontracts::ListContractsRequest {
        contract_type: 0,
        status: "".to_string(),
        participant_id: "".to_string(),
        limit: 100,
    };
    let response = client.list_contracts(request).await;

    assert!(
        response.is_ok(),
        "ListContracts failed: {:?}",
        response.err()
    );
}

// ============================================================================
// TRANSFER TESTS (Read-only validation)
// ============================================================================

#[tokio::test]
async fn test_transfer_with_empty_entries_is_noop() {
    let channel = connect().await.expect("Server not running");
    let mut client = LedgerServiceClient::new(channel);

    let request = ledger::TransferRequest {
        entries: vec![],
        reference: "test_empty_transfer".to_string(),
    };
    let response = client.transfer(request).await;

    // Empty transfer is accepted as a no-op (server creates a transaction with no entries)
    assert!(
        response.is_ok(),
        "Empty transfer should succeed as no-op: {:?}",
        response.err()
    );
}

#[tokio::test]
async fn test_transfer_with_invalid_account_fails() {
    let channel = connect().await.expect("Server not running");
    let mut client = LedgerServiceClient::new(channel);

    let request = ledger::TransferRequest {
        entries: vec![
            common::TransferEntry {
                account_id: "fake_sender:operating".to_string(),
                amount: -100,
            },
            common::TransferEntry {
                account_id: "fake_receiver:operating".to_string(),
                amount: 100,
            },
        ],
        reference: "test_invalid_accounts".to_string(),
    };
    let response = client.transfer(request).await;

    assert!(
        response.is_err(),
        "Expected error for transfer with invalid accounts"
    );
}

// ============================================================================
// PROPERTY: API CONSISTENCY
// ============================================================================

#[tokio::test]
async fn test_participant_accounts_match_participant_id() {
    let channel = connect().await.expect("Server not running");
    let mut client = ParticipantServiceClient::new(channel);

    // Get all participants
    let list_req = business::ListParticipantsRequest { role: 0 };
    let participants = client
        .list_participants(list_req)
        .await
        .unwrap()
        .into_inner()
        .participants;

    // For each participant, verify their accounts belong to them
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

        for account in accounts {
            assert_eq!(
                account.participant_id, participant.id,
                "Account {} belongs to {} but was returned for {}",
                account.id, account.participant_id, participant.id
            );
        }
    }
}
