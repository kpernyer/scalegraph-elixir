//! Application State and Logic
//!
//! This module defines the core application state and business logic for the
//! Scalegraph CLI. It manages:
//!
//! - Application state (participants, accounts, transactions)
//! - User input handling and navigation
//! - Data loading from the gRPC server
//! - Transfer form state and validation
//! - View management and transitions
//!
//! The `App` struct is the central state container, and `run_app` is the
//! main event loop that processes user input and updates the UI.

use crate::grpc::{self, ScalegraphClient};
use anyhow::Result;
use crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers};
use ratatui::{backend::CrosstermBackend, widgets::ListState, Terminal};
use std::io::Stdout;

pub type AppResult<T> = Result<T>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum View {
    Participants,
    ParticipantDetail,
    Transfer,
    History,
    Future,
}

impl View {
    pub fn all() -> Vec<View> {
        // Only include flat navigation views (tabs), not hierarchical views
        // ParticipantDetail is accessed by drilling down from Participants, not via tabs
        vec![
            View::Participants,
            View::Transfer,
            View::History,
            View::Future,
        ]
    }

    pub fn title(&self) -> &'static str {
        match self {
            View::Participants => "Participants",
            View::ParticipantDetail => "Participant Details",
            View::Transfer => "Transfer",
            View::History => "History",
            View::Future => "Future",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ContactInfo {
    pub email: String,
    pub phone: String,
    pub website: String,
    pub address: String,
    pub postal_code: String,
    pub city: String,
    pub country: String,
}

#[derive(Debug, Clone)]
pub struct ParticipantInfo {
    pub id: String,
    pub name: String,
    pub role: String,
    pub services: Vec<String>,
    pub created_at: Option<i64>,
    pub metadata: std::collections::HashMap<String, String>,
    pub about: String,
    pub contact: ContactInfo,
}

#[derive(Debug, Clone)]
pub struct ContractInfo {
    pub id: String,
    pub contract_type: String,
    pub description: String,
    pub participants: Vec<String>, // Other participants in the contract
    pub next_execution: Option<i64>, // Next execution time in milliseconds
}

#[derive(Debug, Clone)]
pub struct ParticipantDetail {
    pub info: ParticipantInfo,
    pub accounts: Vec<AccountInfo>,
    pub total_balance: i64,
    pub contracts: Vec<ContractInfo>,
}

#[derive(Debug, Clone)]
pub struct AccountInfo {
    pub id: String,
    #[allow(dead_code)]
    pub participant_id: String,
    pub account_type: String,
    pub balance: i64,
}

#[derive(Debug, Clone, Default)]
pub struct TransferForm {
    pub from_account: String,
    pub to_account: String,
    pub amount: String,
    pub reference: String,
    pub selected_field: usize,
    pub error: Option<String>,
    pub success: Option<String>,
    pub suggestion_index: Option<usize>,
    pub show_suggestions: bool,
}

#[derive(Debug, Clone)]
pub struct FutureEvent {
    pub contract_id: String,
    pub contract_type: String,
    pub description: String,
    pub execution_time: i64, // Unix timestamp in milliseconds
}

#[derive(Debug, Clone)]
pub struct BreadcrumbSegment {
    pub label: String,
    pub view: View,
    pub context: Option<String>, // e.g., participant_id when viewing participant's accounts
}

pub struct App {
    pub client: ScalegraphClient,
    pub current_view: View,
    pub running: bool,

    // Breadcrumb navigation
    pub breadcrumb: Vec<BreadcrumbSegment>,

    // Participants view
    pub participants: Vec<ParticipantInfo>,
    pub participant_state: ListState,

    // Participant detail view
    pub participant_detail: Option<ParticipantDetail>,

    // Accounts (for transfer form)
    pub accounts: Vec<AccountInfo>,
    pub account_state: ListState,

    // Transfer view
    pub transfer_form: TransferForm,

    // History
    pub history: Vec<String>,

    // Future (scheduled events)
    pub future_events: Vec<FutureEvent>,

    // Status
    #[allow(dead_code)]
    pub status_message: Option<String>,
    pub loading: bool,
}

impl App {
    pub fn new(client: ScalegraphClient) -> Self {
        let mut participant_state = ListState::default();
        participant_state.select(Some(0));

        let mut account_state = ListState::default();
        account_state.select(Some(0));

        let mut app = Self {
            client,
            current_view: View::Participants,
            running: true,
            breadcrumb: Vec::new(),
            participants: Vec::new(),
            participant_state,
            participant_detail: None,
            accounts: Vec::new(),
            account_state,
            transfer_form: TransferForm::default(),
            history: Vec::new(),
            future_events: Vec::new(),
            status_message: None,
            loading: false,
        };
        app.update_breadcrumb();
        app
    }

    pub async fn load_participants(&mut self) -> Result<()> {
        self.loading = true;
        let participants = self.client.list_participants(None).await?;
        self.participants = participants
            .into_iter()
            .map(|p| {
                let contact = p.contact.as_ref().map(|c| ContactInfo {
                    email: c.email.clone(),
                    phone: c.phone.clone(),
                    website: c.website.clone(),
                    address: c.address.clone(),
                    postal_code: c.postal_code.clone(),
                    city: c.city.clone(),
                    country: c.country.clone(),
                }).unwrap_or_else(|| ContactInfo {
                    email: String::new(),
                    phone: String::new(),
                    website: String::new(),
                    address: String::new(),
                    postal_code: String::new(),
                    city: String::new(),
                    country: String::new(),
                });
                
                ParticipantInfo {
                    id: p.id,
                    name: p.name,
                    role: grpc::role_to_string(p.role).to_string(),
                    services: p.services,
                    created_at: if p.created_at > 0 { Some(p.created_at) } else { None },
                    metadata: p.metadata,
                    about: p.about,
                    contact,
                }
            })
            .collect();
        self.loading = false;
        Ok(())
    }

    pub async fn load_participant_detail(&mut self, participant_id: &str) -> Result<()> {
        self.loading = true;
        
        // Load full participant details
        let participant = self.client.get_participant(participant_id).await?;
        
        // Load accounts for this participant
        let accounts = self.client.get_participant_accounts(participant_id).await?;
        
        let account_infos: Vec<AccountInfo> = accounts
            .iter()
            .map(|acc| AccountInfo {
                id: acc.id.clone(),
                participant_id: acc.participant_id.clone(),
                account_type: grpc::account_type_to_string(acc.account_type).to_string(),
                balance: acc.balance,
            })
            .collect();
        
        // Calculate total balance
        let total_balance: i64 = account_infos.iter().map(|a| a.balance).sum();
        
        // Load contracts for this participant
        let contracts = self.client.list_contracts(None, None, Some(participant_id.to_string()), Some(100)).await.unwrap_or_default();
        
        let contract_infos: Vec<ContractInfo> = contracts
            .into_iter()
            .map(|contract_resp| {
                use crate::grpc::smartcontracts::contract_response::Contract;
                match contract_resp.contract {
                    Some(Contract::Invoice(inv)) => {
                        let mut participants = vec![inv.supplier_id.clone(), inv.buyer_id.clone()];
                        participants.retain(|p| p != participant_id);
                        ContractInfo {
                            id: inv.id,
                            contract_type: "Invoice".to_string(),
                            description: format!("Invoice: {} from {} to {}", 
                                grpc::format_balance(inv.amount_cents),
                                inv.supplier_id,
                                inv.buyer_id),
                            participants,
                            next_execution: if inv.due_date > 0 { Some(inv.due_date) } else { None },
                        }
                    }
                    Some(Contract::Subscription(sub)) => {
                        let mut participants = vec![sub.provider_id.clone(), sub.subscriber_id.clone()];
                        participants.retain(|p| p != participant_id);
                        ContractInfo {
                            id: sub.id,
                            contract_type: "Subscription".to_string(),
                            description: format!("Subscription: {} monthly from {} to {}", 
                                grpc::format_balance(sub.monthly_fee_cents),
                                sub.provider_id,
                                sub.subscriber_id),
                            participants,
                            next_execution: if sub.next_billing_date > 0 { Some(sub.next_billing_date) } else { None },
                        }
                    }
                    Some(Contract::Generic(gen)) => {
                        // Extract participants from metadata if available
                        let participants = Self::extract_participants_from_metadata(&gen.metadata, participant_id);
                        ContractInfo {
                            id: gen.id.clone(),
                            contract_type: format!("Generic ({})", Self::contract_type_to_string(gen.contract_type)),
                            description: format!("{}: {}", gen.name, gen.description),
                            participants,
                            next_execution: if gen.next_execution_at > 0 { Some(gen.next_execution_at) } else { None },
                        }
                    }
                    Some(Contract::ConditionalPayment(cp)) => {
                        let mut participants = vec![cp.payer_id.clone(), cp.receiver_id.clone()];
                        participants.retain(|p| p != participant_id);
                        ContractInfo {
                            id: cp.id,
                            contract_type: "Conditional Payment".to_string(),
                            description: format!("Conditional Payment: {} from {} to {}", 
                                grpc::format_balance(cp.amount_cents),
                                cp.payer_id,
                                cp.receiver_id),
                            participants,
                            next_execution: None, // Conditional payments don't have scheduled execution
                        }
                    }
                    Some(Contract::RevenueShare(rs)) => {
                        let participant_ids: Vec<String> = rs.parties.iter()
                            .map(|p| p.participant_id.clone())
                            .filter(|p| p != participant_id)
                            .collect();
                        ContractInfo {
                            id: rs.id,
                            contract_type: "Revenue Share".to_string(),
                            description: format!("Revenue Share: {} parties for {}", 
                                rs.parties.len(),
                                rs.transaction_type),
                            participants: participant_ids,
                            next_execution: None, // Revenue share is event-driven
                        }
                    }
                    None => ContractInfo {
                        id: "unknown".to_string(),
                        contract_type: "Unknown".to_string(),
                        description: "Unknown contract type".to_string(),
                        participants: vec![],
                        next_execution: None,
                    }
                }
            })
            .collect();
        
        let contact = participant.contact.as_ref().map(|c| ContactInfo {
            email: c.email.clone(),
            phone: c.phone.clone(),
            website: c.website.clone(),
            address: c.address.clone(),
            postal_code: c.postal_code.clone(),
            city: c.city.clone(),
            country: c.country.clone(),
        }).unwrap_or_else(|| ContactInfo {
            email: String::new(),
            phone: String::new(),
            website: String::new(),
            address: String::new(),
            postal_code: String::new(),
            city: String::new(),
            country: String::new(),
        });
        
        let info = ParticipantInfo {
            id: participant.id,
            name: participant.name,
            role: grpc::role_to_string(participant.role).to_string(),
            services: participant.services,
            created_at: if participant.created_at > 0 { Some(participant.created_at) } else { None },
            metadata: participant.metadata,
            about: participant.about,
            contact,
        };
        
        self.participant_detail = Some(ParticipantDetail {
            info,
            accounts: account_infos,
            total_balance,
            contracts: contract_infos,
        });
        
        self.loading = false;
        Ok(())
    }

    pub async fn load_accounts(&mut self) -> Result<()> {
        self.loading = true;
        self.accounts.clear();

        for participant in &self.participants {
            if let Ok(accounts) = self.client.get_participant_accounts(&participant.id).await {
                for acc in accounts {
                    self.accounts.push(AccountInfo {
                        id: acc.id,
                        participant_id: acc.participant_id,
                        account_type: grpc::account_type_to_string(acc.account_type).to_string(),
                        balance: acc.balance,
                    });
                }
            }
        }

        self.loading = false;
        Ok(())
    }

    pub async fn load_future_events(&mut self) -> Result<()> {
        self.loading = true;
        self.future_events.clear();

        // Load all contracts
        let contracts = self.client.list_contracts(None, Some("active".to_string()), None, Some(100)).await.unwrap_or_default();
        
        let mut events: Vec<FutureEvent> = Vec::new();
        let now = chrono::Utc::now().timestamp_millis();
        
        use crate::grpc::smartcontracts::contract_response::Contract;
        for contract_resp in contracts {
            match contract_resp.contract {
                Some(Contract::Invoice(inv)) => {
                    if inv.due_date > now && inv.status == "pending" {
                        events.push(FutureEvent {
                            contract_id: inv.id,
                            contract_type: "Invoice".to_string(),
                            description: format!("Invoice payment: {} from {} to {}", 
                                grpc::format_balance(inv.amount_cents),
                                inv.supplier_id,
                                inv.buyer_id),
                            execution_time: inv.due_date,
                        });
                    }
                }
                Some(Contract::Subscription(sub)) => {
                    if sub.next_billing_date > now && sub.status == "active" {
                        events.push(FutureEvent {
                            contract_id: sub.id,
                            contract_type: "Subscription".to_string(),
                            description: format!("Subscription billing: {} from {} to {}", 
                                grpc::format_balance(sub.monthly_fee_cents),
                                sub.provider_id,
                                sub.subscriber_id),
                            execution_time: sub.next_billing_date,
                        });
                    }
                }
                Some(Contract::Generic(gen)) => {
                    // Handle generic contracts (YAML-based)
                    if gen.next_execution_at > now && gen.status == 1 {  // 1 = ACTIVE
                        events.push(FutureEvent {
                            contract_id: gen.id.clone(),
                            contract_type: format!("Generic ({})", Self::contract_type_to_string(gen.contract_type)),
                            description: format!("{}: {}", gen.name, gen.description),
                            execution_time: gen.next_execution_at,
                        });
                    }
                }
                _ => {} // Conditional payments and revenue share don't have scheduled execution
            }
        }
        
        // Sort by execution time and take top 5
        events.sort_by_key(|e| e.execution_time);
        self.future_events = events.into_iter().take(5).collect();
        
        self.loading = false;
        Ok(())
    }

    // Helper functions for generic contracts

    fn contract_type_to_string(contract_type: i32) -> String {
        match contract_type {
            0 => "Generic".to_string(),
            1 => "Loan".to_string(),
            2 => "Invoice".to_string(),
            3 => "Subscription".to_string(),
            4 => "Conditional Payment".to_string(),
            5 => "Revenue Share".to_string(),
            6 => "Supplier Registration".to_string(),
            7 => "Ecosystem Partner Membership".to_string(),
            _ => format!("Unknown ({})", contract_type),
        }
    }

    fn extract_participants_from_metadata(metadata: &std::collections::HashMap<String, String>, exclude_id: &str) -> Vec<String> {
        let mut participants = Vec::new();
        
        // Common participant ID fields in metadata
        let participant_fields = vec!["supplier_id", "buyer_id", "provider_id", "subscriber_id", 
                                       "payer_id", "receiver_id", "orchestrator_id", "first_provider_id"];
        
        for field in participant_fields {
            if let Some(id) = metadata.get(field) {
                if id != exclude_id && !participants.contains(id) {
                    participants.push(id.clone());
                }
            }
        }
        
        participants
    }

    pub async fn load_transactions(&mut self) -> Result<()> {
        self.loading = true;
        self.history.clear();

        if let Ok(transactions) = self.client.list_transactions(Some(50), None).await {
            for tx in transactions {
                // Format each transaction as a string for display
                let entries_str: Vec<String> = tx
                    .entries
                    .iter()
                    .map(|e| format!("{}: {}", e.account_id, grpc::format_balance(e.amount)))
                    .collect();

                let msg = format!(
                    "[{}] {} | {} | {}",
                    &tx.id[..8],
                    tx.r#type,
                    entries_str.join(", "),
                    tx.reference
                );
                self.history.push(msg);
            }
        }

        self.loading = false;
        Ok(())
    }

    pub async fn execute_transfer(&mut self) -> Result<()> {
        self.transfer_form.error = None;
        self.transfer_form.success = None;

        let amount: i64 = match self.transfer_form.amount.parse() {
            Ok(a) => a,
            Err(_) => {
                self.transfer_form.error = Some("Invalid amount".to_string());
                return Ok(());
            }
        };

        if self.transfer_form.from_account.is_empty() || self.transfer_form.to_account.is_empty() {
            self.transfer_form.error = Some("Both accounts required".to_string());
            return Ok(());
        }

        let entries = vec![
            (self.transfer_form.from_account.clone(), -amount),
            (self.transfer_form.to_account.clone(), amount),
        ];

        match self
            .client
            .transfer(entries, &self.transfer_form.reference)
            .await
        {
            Ok(tx) => {
                let msg = format!(
                    "Transfer {} from {} to {} (ref: {}, tx: {})",
                    grpc::format_balance(amount),
                    self.transfer_form.from_account,
                    self.transfer_form.to_account,
                    self.transfer_form.reference,
                    tx.id
                );
                self.history.push(msg.clone());
                self.transfer_form.success = Some(format!("Success! TX: {}", tx.id));
                self.transfer_form = TransferForm {
                    success: self.transfer_form.success.clone(),
                    ..Default::default()
                };
            }
            Err(e) => {
                self.transfer_form.error = Some(format!("Failed: {}", e));
            }
        }

        Ok(())
    }

    /// Update breadcrumb based on current view and context.
    /// 
    /// Breadcrumbs represent the hierarchical navigation dimension (drilling down into data),
    /// while Tab/arrows represent the flat navigation dimension (switching between view types).
    /// 
    /// Examples:
    /// - Flat: Participants ↔ Accounts ↔ Transfer ↔ History (Tab/arrows)
    /// - Hierarchical: Participants → [Participant] → Accounts (breadcrumb/back)
    pub fn update_breadcrumb(&mut self) {
        self.breadcrumb.clear();

        match self.current_view {
            View::Participants => {
                self.breadcrumb.push(BreadcrumbSegment {
                    label: "Participants".to_string(),
                    view: View::Participants,
                    context: None,
                });
            }
            View::ParticipantDetail => {
                self.breadcrumb.push(BreadcrumbSegment {
                    label: "Participants".to_string(),
                    view: View::Participants,
                    context: None,
                });
                
                if let Some(ref detail) = self.participant_detail {
                    self.breadcrumb.push(BreadcrumbSegment {
                        label: detail.info.name.clone(),
                        view: View::ParticipantDetail,
                        context: Some(detail.info.id.clone()),
                    });
                }
            }
            View::Transfer => {
                self.breadcrumb.push(BreadcrumbSegment {
                    label: "Transfer".to_string(),
                    view: View::Transfer,
                    context: None,
                });
            }
            View::History => {
                self.breadcrumb.push(BreadcrumbSegment {
                    label: "History".to_string(),
                    view: View::History,
                    context: None,
                });
            }
            View::Future => {
                self.breadcrumb.push(BreadcrumbSegment {
                    label: "Future".to_string(),
                    view: View::Future,
                    context: None,
                });
            }
        }
    }

    /// Navigate to a breadcrumb segment (hierarchical navigation).
    /// This moves up/down the data hierarchy, not between parallel views.
    /// Use Tab/arrows for switching between parallel views.
    pub fn navigate_to_breadcrumb(&mut self, index: usize) {
        if index < self.breadcrumb.len() {
            let segment = &self.breadcrumb[index];
            self.current_view = segment.view;
            
            // Truncate breadcrumb to selected segment
            self.breadcrumb.truncate(index + 1);
            self.update_breadcrumb();
        }
    }

    /// Navigate to next view in the flat navigation dimension.
    /// This switches between parallel views (Participants, ParticipantDetail, Transfer, History, Future),
    /// not hierarchical drill-down. Use breadcrumb/back for hierarchical navigation.
    pub fn next_view(&mut self) {
        let views = View::all();
        let idx = views
            .iter()
            .position(|v| *v == self.current_view)
            .unwrap_or(0);
        self.current_view = views[(idx + 1) % views.len()];
        self.update_breadcrumb();
    }

    /// Navigate to previous view in the flat navigation dimension.
    /// This switches between parallel views, not hierarchical drill-down.
    pub fn prev_view(&mut self) {
        let views = View::all();
        let idx = views
            .iter()
            .position(|v| *v == self.current_view)
            .unwrap_or(0);
        self.current_view = views[(idx + views.len() - 1) % views.len()];
        self.update_breadcrumb();
    }

    /// Jump directly to a view by index in the flat navigation dimension.
    /// This switches between parallel views, not hierarchical drill-down.
    pub fn goto_view(&mut self, index: usize) {
        let views = View::all();
        if index < views.len() {
            self.current_view = views[index];
            self.update_breadcrumb();
        }
    }

    pub fn select_next(&mut self) {
        match self.current_view {
            View::Participants => {
                let i = self.participant_state.selected().unwrap_or(0);
                if i < self.participants.len().saturating_sub(1) {
                    self.participant_state.select(Some(i + 1));
                }
            }
            View::Transfer => {
                self.transfer_form.selected_field = (self.transfer_form.selected_field + 1) % 4;
            }
            _ => {}
        }
    }

    pub fn select_prev(&mut self) {
        match self.current_view {
            View::Participants => {
                let i = self.participant_state.selected().unwrap_or(0);
                if i > 0 {
                    self.participant_state.select(Some(i - 1));
                }
            }
            View::Transfer => {
                self.transfer_form.selected_field = (self.transfer_form.selected_field + 3) % 4;
            }
            _ => {}
        }
    }

    pub fn handle_char(&mut self, c: char) {
        if self.current_view == View::Transfer {
            let field = match self.transfer_form.selected_field {
                0 => &mut self.transfer_form.from_account,
                1 => &mut self.transfer_form.to_account,
                2 => &mut self.transfer_form.amount,
                3 => &mut self.transfer_form.reference,
                _ => return,
            };
            field.push(c);
            // Show suggestions when typing in account fields
            self.transfer_form.suggestion_index = None;
            self.transfer_form.show_suggestions = self.transfer_form.selected_field <= 1;
        }
    }

    pub fn handle_backspace(&mut self) {
        if self.current_view == View::Transfer {
            let field = match self.transfer_form.selected_field {
                0 => &mut self.transfer_form.from_account,
                1 => &mut self.transfer_form.to_account,
                2 => &mut self.transfer_form.amount,
                3 => &mut self.transfer_form.reference,
                _ => return,
            };
            field.pop();
            // Reset suggestions when typing
            self.transfer_form.suggestion_index = None;
            self.transfer_form.show_suggestions = self.transfer_form.selected_field <= 1;
        }
    }

    /// Get filtered account suggestions for the current transfer form field
    pub fn get_account_suggestions(&self) -> Vec<&AccountInfo> {
        let filter = match self.transfer_form.selected_field {
            0 => &self.transfer_form.from_account,
            1 => &self.transfer_form.to_account,
            _ => return vec![],
        };

        let filter_lower = filter.to_lowercase();
        self.accounts
            .iter()
            .filter(|acc| {
                filter.is_empty()
                    || acc.id.to_lowercase().contains(&filter_lower)
                    || acc.account_type.to_lowercase().contains(&filter_lower)
            })
            .collect()
    }

    /// Cycle to next account suggestion
    pub fn next_suggestion(&mut self) {
        if self.current_view != View::Transfer || self.transfer_form.selected_field > 1 {
            return;
        }

        // Get suggestion IDs first to avoid borrow issues
        let suggestion_ids: Vec<String> = self
            .get_account_suggestions()
            .iter()
            .map(|acc| acc.id.clone())
            .collect();

        if suggestion_ids.is_empty() {
            return;
        }

        self.transfer_form.show_suggestions = true;
        let new_index = match self.transfer_form.suggestion_index {
            None => 0,
            Some(i) => (i + 1) % suggestion_ids.len(),
        };
        self.transfer_form.suggestion_index = Some(new_index);

        // Apply the suggestion to the field
        if let Some(acc_id) = suggestion_ids.get(new_index) {
            match self.transfer_form.selected_field {
                0 => self.transfer_form.from_account = acc_id.clone(),
                1 => self.transfer_form.to_account = acc_id.clone(),
                _ => {}
            }
        }
    }

    /// Cycle to previous account suggestion
    pub fn prev_suggestion(&mut self) {
        if self.current_view != View::Transfer || self.transfer_form.selected_field > 1 {
            return;
        }

        // Get suggestion IDs first to avoid borrow issues
        let suggestion_ids: Vec<String> = self
            .get_account_suggestions()
            .iter()
            .map(|acc| acc.id.clone())
            .collect();

        if suggestion_ids.is_empty() {
            return;
        }

        self.transfer_form.show_suggestions = true;
        let new_index = match self.transfer_form.suggestion_index {
            None => suggestion_ids.len() - 1,
            Some(i) => {
                if i == 0 {
                    suggestion_ids.len() - 1
                } else {
                    i - 1
                }
            }
        };
        self.transfer_form.suggestion_index = Some(new_index);

        // Apply the suggestion to the field
        if let Some(acc_id) = suggestion_ids.get(new_index) {
            match self.transfer_form.selected_field {
                0 => self.transfer_form.from_account = acc_id.clone(),
                1 => self.transfer_form.to_account = acc_id.clone(),
                _ => {}
            }
        }
    }

    /// Accept current suggestion and move to next field
    pub fn accept_suggestion(&mut self) {
        self.transfer_form.suggestion_index = None;
        self.transfer_form.show_suggestions = false;
        // Move to next field
        self.transfer_form.selected_field = (self.transfer_form.selected_field + 1) % 4;
    }
}

pub async fn run_app(
    terminal: &mut Terminal<CrosstermBackend<Stdout>>,
    mut app: App,
) -> AppResult<()> {
    // Initial data load - ignore errors to show UI even if server has issues
    let _ = app.load_participants().await;
    let _ = app.load_accounts().await;
    let _ = app.load_transactions().await;
    let _ = app.load_future_events().await;

    loop {
        terminal.draw(|f| super::views::draw(f, &mut app))?;

        if event::poll(std::time::Duration::from_millis(100))? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    // Handle Ctrl+C
                    if key.modifiers.contains(KeyModifiers::CONTROL)
                        && key.code == KeyCode::Char('c')
                    {
                        app.running = false;
                        continue;
                    }

                    match key.code {
                        KeyCode::Char('q') => {
                            // 'q' always quits, even in Transfer view
                            app.running = false;
                        }
                        KeyCode::Esc => {
                            // Esc clears form in Transfer view, quits elsewhere
                            if app.current_view == View::Transfer {
                                app.transfer_form = TransferForm::default();
                            } else {
                                app.running = false;
                            }
                        }
                        // Tab navigation - in Transfer form, Tab cycles through account suggestions
                        KeyCode::Tab => {
                            if app.current_view == View::Transfer
                                && app.transfer_form.selected_field <= 1
                            {
                                app.next_suggestion();
                            } else {
                                let was_transfer = app.current_view == View::Transfer;
                                app.next_view();
                                // Reload data when entering views
                                if !was_transfer && app.current_view == View::Transfer {
                                    let _ = app.load_accounts().await;
                                } else if app.current_view == View::Future {
                                    let _ = app.load_future_events().await;
                                }
                            }
                        }
                        KeyCode::BackTab => {
                            if app.current_view == View::Transfer
                                && app.transfer_form.selected_field <= 1
                            {
                                app.prev_suggestion();
                            } else {
                                let was_transfer = app.current_view == View::Transfer;
                                app.prev_view();
                                // Reload data when entering views
                                if !was_transfer && app.current_view == View::Transfer {
                                    let _ = app.load_accounts().await;
                                } else if app.current_view == View::Future {
                                    let _ = app.load_future_events().await;
                                }
                            }
                        }
                        KeyCode::Right => {
                            // Right arrow always switches to next tab
                            let was_transfer = app.current_view == View::Transfer;
                            app.next_view();
                            // Reload data when entering views
                            if !was_transfer && app.current_view == View::Transfer {
                                let _ = app.load_accounts().await;
                            } else if app.current_view == View::Future {
                                let _ = app.load_future_events().await;
                            }
                        }
                        KeyCode::Left => {
                            // Left arrow always switches to previous tab
                            let was_transfer = app.current_view == View::Transfer;
                            app.prev_view();
                            // Reload data when entering views
                            if !was_transfer && app.current_view == View::Transfer {
                                let _ = app.load_accounts().await;
                            } else if app.current_view == View::Future {
                                let _ = app.load_future_events().await;
                            }
                        }
                        // Number keys for direct tab access (not in Transfer view)
                        KeyCode::Char('1') if app.current_view != View::Transfer => {
                            app.goto_view(0);
                        }
                        KeyCode::Char('2') if app.current_view != View::Transfer => {
                            app.goto_view(1);
                        }
                        KeyCode::Char('3') if app.current_view != View::Transfer => {
                            // Entering Transfer view - load all accounts
                            app.goto_view(2);
                            let _ = app.load_accounts().await;
                        }
                        KeyCode::Char('4') if app.current_view != View::Transfer => {
                            app.goto_view(3);
                            let _ = app.load_future_events().await;
                        }
                        // List navigation
                        KeyCode::Down | KeyCode::Char('j') => {
                            app.select_next();
                        }
                        KeyCode::Up | KeyCode::Char('k') => {
                            app.select_prev();
                        }
                        // Home/End for list navigation
                        KeyCode::Home => match app.current_view {
                            View::Participants => app.participant_state.select(Some(0)),
                            _ => {}
                        },
                        KeyCode::End => match app.current_view {
                            View::Participants => {
                                let len = app.participants.len();
                                if len > 0 {
                                    app.participant_state.select(Some(len - 1));
                                }
                            }
                            _ => {}
                        },
                        // Enter actions
                        KeyCode::Enter => {
                            if app.current_view == View::Transfer {
                                // If in account field (0 or 1), accept and move to next field
                                if app.transfer_form.selected_field <= 1 {
                                    app.accept_suggestion();
                                } else {
                                    // In amount or reference field, execute transfer
                                    let _ = app.execute_transfer().await;
                                }
                            } else if app.current_view == View::Participants {
                                if let Some(idx) = app.participant_state.selected() {
                                    let participant_id =
                                        app.participants.get(idx).map(|p| p.id.clone());
                                    if let Some(pid) = participant_id {
                                        let _ = app.load_participant_detail(&pid).await;
                                        app.current_view = View::ParticipantDetail;
                                        app.update_breadcrumb();
                                    }
                                }
                            }
                        }
                        // Refresh
                        KeyCode::Char('r') if app.current_view != View::Transfer => {
                            let _ = app.load_participants().await;
                            let _ = app.load_accounts().await;
                            let _ = app.load_transactions().await;
                            let _ = app.load_future_events().await;
                            // Reload participant detail if viewing it
                            if app.current_view == View::ParticipantDetail {
                                let participant_id = app.participant_detail.as_ref().map(|d| d.info.id.clone());
                                if let Some(pid) = participant_id {
                                    let _ = app.load_participant_detail(&pid).await;
                                }
                            }
                        }
                        // Back navigation - move up the hierarchical dimension (breadcrumb)
                        // This is different from Tab/arrows which move in the flat dimension
                        KeyCode::Char('b') if app.breadcrumb.len() > 1 => {
                            // Navigate back to previous segment
                            let target_index = app.breadcrumb.len() - 2;
                            app.navigate_to_breadcrumb(target_index);
                            
                            // Reload data based on new view
                            if app.current_view == View::ParticipantDetail {
                                // Reload participant detail if we're going back to it
                                let participant_id = app.participant_detail.as_ref().map(|d| d.info.id.clone());
                                if let Some(pid) = participant_id {
                                    let _ = app.load_participant_detail(&pid).await;
                                }
                            } else if app.current_view == View::Participants {
                                let _ = app.load_participants().await;
                            } else if app.current_view == View::Future {
                                let _ = app.load_future_events().await;
                            }
                        }
                        // Text input for Transfer form
                        KeyCode::Char(c) => {
                            app.handle_char(c);
                        }
                        KeyCode::Backspace => {
                            app.handle_backspace();
                        }
                        _ => {}
                    }
                }
            }
        }

        if !app.running {
            return Ok(());
        }
    }
}
