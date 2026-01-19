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
    SmartContracts,
    Transfer,
    History,
    Future,
    CreateContract,
}

impl View {
    pub fn all() -> Vec<View> {
        // Only include flat navigation views (tabs), not hierarchical views
        // ParticipantDetail is accessed by drilling down from Participants, not via tabs
        vec![
            View::Participants,
            View::SmartContracts,
            View::Transfer,
            View::History,
            View::Future,
            View::CreateContract,
        ]
    }

    pub fn title(&self) -> &'static str {
        match self {
            View::Participants => "Participants",
            View::ParticipantDetail => "Participant Details",
            View::SmartContracts => "Contracts",
            View::Transfer => "Transfer",
            View::History => "History",
            View::Future => "Future",
            View::CreateContract => "Create Contract",
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
    pub created_at: Option<i64>, // Creation timestamp in milliseconds
    pub giving_partner: Option<String>, // Partner that gives/pays (e.g., buyer, subscriber, payer)
    pub receiving_partner: Option<String>, // Partner that receives (e.g., supplier, provider, receiver)
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
pub struct ContractTemplate {
    pub name: String,
    pub path: String,
    pub description: String,
}

#[derive(Debug, Clone)]
pub struct ContractForm {
    // Step 1: Template selection
    pub templates: Vec<ContractTemplate>,
    pub selected_template_index: Option<usize>,
    pub template_content: Option<String>,
    
    // Step 2: Variable input
    pub variables: Vec<(String, String)>, // (variable_name, value)
    pub selected_variable_index: usize,
    pub account_suggestion_index: Option<usize>,
    pub show_account_suggestions: bool,
    
    // State
    pub step: ContractFormStep,
    pub error: Option<String>,
    pub success: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VariableType {
    Timestamp,  // Unix timestamp in milliseconds (i64)
    Amount,     // Amount in cents (i64)
    Count,      // Integer count
    String,     // Plain string
}

impl VariableType {
    pub fn detect(var_name: &str) -> Self {
        let name_lower = var_name.to_lowercase();
        
        // Timestamp fields
        if name_lower.contains("_at") || 
           name_lower.contains("_date") || 
           name_lower == "expires_at" ||
           name_lower == "created_at" ||
           name_lower == "due_date" ||
           name_lower == "first_payment_date" ||
           name_lower == "next_billing_date" ||
           name_lower == "loan_end_date" ||
           name_lower == "issue_date" {
            return VariableType::Timestamp;
        }
        
        // Amount fields
        if name_lower.contains("amount") || 
           name_lower.contains("_cents") ||
           name_lower.contains("fee") ||
           name_lower.contains("payment") && name_lower.contains("cents") {
            return VariableType::Amount;
        }
        
        // Count fields
        if name_lower.contains("total") && name_lower.contains("payment") ||
           name_lower.contains("num_") ||
           name_lower == "total_payments" ||
           name_lower == "num_payments" {
            return VariableType::Count;
        }
        
        VariableType::String
    }
    
    pub fn format_hint(&self) -> &'static str {
        match self {
            VariableType::Timestamp => "Date/time (e.g., 2024-12-20, 2024-12-20 15:30, now, today, +7 days)",
            VariableType::Amount => "Amount in cents, integer only (e.g., 5000 for 50.00)",
            VariableType::Count => "Integer count (e.g., 12)",
            VariableType::String => "Text string",
        }
    }
    
    pub fn validate(&self, value: &str) -> Result<(), String> {
        if value.trim().is_empty() {
            return Err("Value cannot be empty".to_string());
        }
        
        match self {
            VariableType::Timestamp => {
                // Try to parse as human-readable date first, then as Unix timestamp
                Self::parse_timestamp(value)
                    .map(|_| ())
                    .map_err(|e| format!("Invalid date/time: {}. Examples: 2024-12-20, 2024-12-20 15:30, now, today, +7 days", e))
            }
            VariableType::Amount => {
                let amount = value.parse::<i64>()
                    .map_err(|_| format!("Invalid amount. Expected integer in cents (e.g., 5000 for 50.00)"))?;
                if amount < 0 {
                    return Err("Amount cannot be negative".to_string());
                }
                Ok(())
            }
            VariableType::Count => {
                let count = value.parse::<i64>()
                    .map_err(|_| format!("Invalid count. Expected positive integer (e.g., 12)"))?;
                if count < 0 {
                    return Err("Count cannot be negative".to_string());
                }
                Ok(())
            }
            VariableType::String => {
                // Strings are always valid (non-empty is checked above)
                Ok(())
            }
        }
    }
    
    /// Parse a human-readable date/time string and convert to Unix milliseconds
    /// Supports formats like:
    /// - "2024-12-20" (date only, assumes midnight local time)
    /// - "2024-12-20 15:30" (date and time, local time)
    /// - "2024-12-20T15:30:00" (ISO format)
    /// - "today", "tomorrow"
    /// - "+7 days", "+1 month", "+2 weeks" (relative dates)
    /// - Unix timestamp in milliseconds (for backwards compatibility)
    pub fn parse_timestamp(value: &str) -> Result<i64, String> {
        use chrono::{DateTime, Local, NaiveDate, NaiveDateTime, NaiveTime};
        
        let value = value.trim();
        
        // Try parsing as Unix timestamp first (backwards compatibility)
        if let Ok(timestamp) = value.parse::<i64>() {
            // If it's a reasonable timestamp (between 1970 and 2100)
            if timestamp > 0 && timestamp < 4102444800000 {
                return Ok(timestamp);
            }
        }
        
        // Handle relative dates
        if value.starts_with('+') {
            let now = Local::now();
            let parts: Vec<&str> = value[1..].trim().split_whitespace().collect();
            if parts.len() >= 2 {
                let amount: i64 = parts[0].parse()
                    .map_err(|_| "Invalid number in relative date".to_string())?;
                let unit = parts[1].to_lowercase();
                
                let result = match unit.as_str() {
                    "day" | "days" => now + chrono::Duration::days(amount),
                    "week" | "weeks" => now + chrono::Duration::weeks(amount),
                    "month" | "months" => {
                        // Approximate months as 30 days
                        now + chrono::Duration::days(amount * 30)
                    }
                    "year" | "years" => {
                        // Approximate years as 365 days
                        now + chrono::Duration::days(amount * 365)
                    }
                    "hour" | "hours" => now + chrono::Duration::hours(amount),
                    "minute" | "minutes" => now + chrono::Duration::minutes(amount),
                    _ => return Err(format!("Unknown time unit: {}", unit)),
                };
                return Ok(result.timestamp_millis());
            }
        }
        
        // Handle special keywords
        match value.to_lowercase().as_str() {
            "now" | "today" => {
                let now = Local::now();
                return Ok(now.timestamp_millis());
            }
            "tomorrow" => {
                let tomorrow = Local::now() + chrono::Duration::days(1);
                return Ok(tomorrow.timestamp_millis());
            }
            _ => {}
        }
        
        // Try parsing as date with time: "2024-12-20 15:30"
        if let Ok(dt) = NaiveDateTime::parse_from_str(value, "%Y-%m-%d %H:%M") {
            // Convert naive datetime to local datetime
            if let Some(local_dt) = dt.and_local_timezone(Local).single() {
                return Ok(local_dt.timestamp_millis());
            }
        }
        
        // Try RFC3339 format
        if let Ok(dt) = DateTime::parse_from_rfc3339(value) {
            return Ok(dt.timestamp_millis());
        }
        
        // Try ISO format: "2024-12-20T15:30:00"
        if let Ok(dt) = NaiveDateTime::parse_from_str(value, "%Y-%m-%dT%H:%M:%S") {
            if let Some(local_dt) = dt.and_local_timezone(Local).single() {
                return Ok(local_dt.timestamp_millis());
            }
        }
        
        // Try parsing as date only: "2024-12-20"
        if let Ok(date) = NaiveDate::parse_from_str(value, "%Y-%m-%d") {
            let midnight = NaiveTime::from_hms_opt(0, 0, 0).unwrap();
            let dt = date.and_time(midnight);
            if let Some(local_dt) = dt.and_local_timezone(Local).single() {
                return Ok(local_dt.timestamp_millis());
            }
        }
        
        Err("Could not parse date/time. Supported formats: YYYY-MM-DD, YYYY-MM-DD HH:MM, now, today, tomorrow, +N days/weeks/months".to_string())
    }
    
    /// Convert a timestamp (Unix milliseconds) to a human-readable string
    pub fn format_timestamp(timestamp_ms: i64) -> String {
        use chrono::{DateTime, Local, Utc};
        if let Some(dt) = DateTime::from_timestamp_millis(timestamp_ms) {
            let local_dt = dt.with_timezone(&Local);
            local_dt.format("%Y-%m-%d %H:%M:%S").to_string()
        } else {
            timestamp_ms.to_string()
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ContractFormStep {
    SelectTemplate,
    FillVariables,
}

impl Default for ContractForm {
    fn default() -> Self {
        Self {
            templates: Vec::new(),
            selected_template_index: None,
            template_content: None,
            variables: Vec::new(),
            selected_variable_index: 0,
            account_suggestion_index: None,
            show_account_suggestions: false,
            step: ContractFormStep::SelectTemplate,
            error: None,
            success: None,
        }
    }
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

    // Create Contract view
    pub contract_form: ContractForm,

    // History
    pub history: Vec<String>,

    // Future (scheduled events)
    pub future_events: Vec<FutureEvent>,

    // Smart Contracts view
    pub smart_contracts: Vec<ContractInfo>,

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
            contract_form: ContractForm::default(),
            history: Vec::new(),
            future_events: Vec::new(),
            smart_contracts: Vec::new(),
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
                            id: inv.id.clone(),
                            contract_type: "Invoice".to_string(),
                            description: format!("Invoice: {} from {} to {}", 
                                grpc::format_balance(inv.amount_cents),
                                inv.supplier_id,
                                inv.buyer_id),
                            participants,
                            next_execution: if inv.due_date > 0 { Some(inv.due_date) } else { None },
                            created_at: None,
                            giving_partner: Some(inv.buyer_id.clone()),
                            receiving_partner: Some(inv.supplier_id.clone()),
                        }
                    }
                    Some(Contract::Subscription(sub)) => {
                        let mut participants = vec![sub.provider_id.clone(), sub.subscriber_id.clone()];
                        participants.retain(|p| p != participant_id);
                        ContractInfo {
                            id: sub.id.clone(),
                            contract_type: "Subscription".to_string(),
                            description: format!("Subscription: {} monthly from {} to {}", 
                                grpc::format_balance(sub.monthly_fee_cents),
                                sub.provider_id,
                                sub.subscriber_id),
                            participants,
                            next_execution: if sub.next_billing_date > 0 { Some(sub.next_billing_date) } else { None },
                            created_at: None,
                            giving_partner: Some(sub.subscriber_id.clone()),
                            receiving_partner: Some(sub.provider_id.clone()),
                        }
                    }
                    Some(Contract::Generic(gen)) => {
                        // Extract participants from metadata if available
                        let participants = Self::extract_participants_from_metadata(&gen.metadata, participant_id);
                        let giving = gen.metadata.get("payer_id")
                            .or_else(|| gen.metadata.get("buyer_id"))
                            .or_else(|| gen.metadata.get("subscriber_id"))
                            .cloned();
                        let receiving = gen.metadata.get("receiver_id")
                            .or_else(|| gen.metadata.get("supplier_id"))
                            .or_else(|| gen.metadata.get("provider_id"))
                            .cloned();
                        ContractInfo {
                            id: gen.id.clone(),
                            contract_type: format!("Generic ({})", Self::contract_type_to_string(gen.contract_type)),
                            description: format!("{}: {}", gen.name, gen.description),
                            participants,
                            next_execution: if gen.next_execution_at > 0 { Some(gen.next_execution_at) } else { None },
                            created_at: if gen.created_at > 0 { Some(gen.created_at) } else { None },
                            giving_partner: giving,
                            receiving_partner: receiving,
                        }
                    }
                    Some(Contract::ConditionalPayment(cp)) => {
                        let mut participants = vec![cp.payer_id.clone(), cp.receiver_id.clone()];
                        participants.retain(|p| p != participant_id);
                        ContractInfo {
                            id: cp.id.clone(),
                            contract_type: "Conditional Payment".to_string(),
                            description: format!("Conditional Payment: {} from {} to {}", 
                                grpc::format_balance(cp.amount_cents),
                                cp.payer_id,
                                cp.receiver_id),
                            participants,
                            next_execution: None, // Conditional payments don't have scheduled execution
                            created_at: None,
                            giving_partner: Some(cp.payer_id.clone()),
                            receiving_partner: Some(cp.receiver_id.clone()),
                        }
                    }
                    Some(Contract::RevenueShare(rs)) => {
                        let participant_ids: Vec<String> = rs.parties.iter()
                            .map(|p| p.participant_id.clone())
                            .filter(|p| p != participant_id)
                            .collect();
                        ContractInfo {
                            id: rs.id.clone(),
                            contract_type: "Revenue Share".to_string(),
                            description: format!("Revenue Share: {} parties for {}", 
                                rs.parties.len(),
                                rs.transaction_type),
                            participants: participant_ids,
                            next_execution: None, // Revenue share is event-driven
                            created_at: None,
                            giving_partner: None, // Revenue share has multiple parties
                            receiving_partner: None,
                        }
                    }
                    None => ContractInfo {
                        id: "unknown".to_string(),
                        contract_type: "Unknown".to_string(),
                        description: "Unknown contract type".to_string(),
                        participants: vec![],
                        next_execution: None,
                        created_at: None,
                        giving_partner: None,
                        receiving_partner: None,
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
                    // Check if contract is active
                    if gen.status == 1 {  // 1 = ACTIVE
                        // Try to get execution time from next_execution_at first
                        let mut execution_time = gen.next_execution_at;
                        
                        // If next_execution_at is 0 or in the past, try to extract from conditions or metadata
                        if execution_time <= now {
                            // Check metadata for common date fields
                            if let Some(expires_at_str) = gen.metadata.get("expires_at") {
                                if let Ok(expires_at) = expires_at_str.parse::<i64>() {
                                    if expires_at > now {
                                        execution_time = expires_at;
                                    }
                                }
                            } else if let Some(due_date_str) = gen.metadata.get("due_date") {
                                if let Ok(due_date) = due_date_str.parse::<i64>() {
                                    if due_date > now {
                                        execution_time = due_date;
                                    }
                                }
                            } else if let Some(first_payment_str) = gen.metadata.get("first_payment_date") {
                                if let Ok(first_payment) = first_payment_str.parse::<i64>() {
                                    if first_payment > now {
                                        execution_time = first_payment;
                                    }
                                }
                            } else if let Some(next_billing_str) = gen.metadata.get("next_billing_date") {
                                if let Ok(next_billing) = next_billing_str.parse::<i64>() {
                                    if next_billing > now {
                                        execution_time = next_billing;
                                    }
                                }
                            }
                            
                            // If still no valid time, try to extract from conditions
                            if execution_time <= now {
                                for condition in &gen.conditions {
                                    // Check for expires_at in condition parameters
                                    if let Some(expires_at_str) = condition.parameters.get("expires_at") {
                                        if let Ok(expires_at) = expires_at_str.parse::<i64>() {
                                            if expires_at > now {
                                                execution_time = expires_at;
                                                break;
                                            }
                                        }
                                    }
                                    // Check for first_payment_date in condition parameters
                                    if let Some(first_payment_str) = condition.parameters.get("first_payment_date") {
                                        if let Ok(first_payment) = first_payment_str.parse::<i64>() {
                                            if first_payment > now {
                                                execution_time = first_payment;
                                                break;
                                            }
                                        }
                                    }
                                    // Check for next_billing_date in condition parameters
                                    if let Some(next_billing_str) = condition.parameters.get("next_billing_date") {
                                        if let Ok(next_billing) = next_billing_str.parse::<i64>() {
                                            if next_billing > now {
                                                execution_time = next_billing;
                                                break;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Only add event if we found a valid future execution time
                        if execution_time > now {
                            events.push(FutureEvent {
                                contract_id: gen.id.clone(),
                                contract_type: format!("Generic ({})", Self::contract_type_to_string(gen.contract_type)),
                                description: format!("{}: {}", gen.name, gen.description),
                                execution_time,
                            });
                        }
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

    /// Convert a ContractResponse to ContractInfo (for all contracts view)
    fn contract_response_to_info(contract_resp: &crate::grpc::smartcontracts::ContractResponse) -> ContractInfo {
        use crate::grpc::smartcontracts::contract_response::Contract;
        match &contract_resp.contract {
            Some(Contract::Invoice(inv)) => {
                ContractInfo {
                    id: inv.id.clone(),
                    contract_type: "Invoice".to_string(),
                    description: format!("Invoice: {} from {} to {}", 
                        grpc::format_balance(inv.amount_cents),
                        inv.supplier_id,
                        inv.buyer_id),
                    participants: vec![inv.supplier_id.clone(), inv.buyer_id.clone()],
                    next_execution: if inv.due_date > 0 { Some(inv.due_date) } else { None },
                    created_at: None,
                    giving_partner: Some(inv.buyer_id.clone()),
                    receiving_partner: Some(inv.supplier_id.clone()),
                }
            }
            Some(Contract::Subscription(sub)) => {
                ContractInfo {
                    id: sub.id.clone(),
                    contract_type: "Subscription".to_string(),
                    description: format!("Subscription: {} monthly from {} to {}", 
                        grpc::format_balance(sub.monthly_fee_cents),
                        sub.provider_id,
                        sub.subscriber_id),
                    participants: vec![sub.provider_id.clone(), sub.subscriber_id.clone()],
                    next_execution: if sub.next_billing_date > 0 { Some(sub.next_billing_date) } else { None },
                    created_at: None,
                    giving_partner: Some(sub.subscriber_id.clone()),
                    receiving_partner: Some(sub.provider_id.clone()),
                }
            }
            Some(Contract::Generic(gen)) => {
                let participants = Self::extract_participants_from_metadata(&gen.metadata, "");
                let giving = gen.metadata.get("payer_id")
                    .or_else(|| gen.metadata.get("buyer_id"))
                    .or_else(|| gen.metadata.get("subscriber_id"))
                    .cloned();
                let receiving = gen.metadata.get("receiver_id")
                    .or_else(|| gen.metadata.get("supplier_id"))
                    .or_else(|| gen.metadata.get("provider_id"))
                    .cloned();
                ContractInfo {
                    id: gen.id.clone(),
                    contract_type: format!("Generic ({})", Self::contract_type_to_string(gen.contract_type)),
                    description: format!("{}: {}", gen.name, gen.description),
                    participants,
                    next_execution: if gen.next_execution_at > 0 { Some(gen.next_execution_at) } else { None },
                    created_at: if gen.created_at > 0 { Some(gen.created_at) } else { None },
                    giving_partner: giving,
                    receiving_partner: receiving,
                }
            }
            Some(Contract::ConditionalPayment(cp)) => {
                ContractInfo {
                    id: cp.id.clone(),
                    contract_type: "Conditional Payment".to_string(),
                    description: format!("Conditional Payment: {} from {} to {}", 
                        grpc::format_balance(cp.amount_cents),
                        cp.payer_id,
                        cp.receiver_id),
                    participants: vec![cp.payer_id.clone(), cp.receiver_id.clone()],
                    next_execution: None,
                    created_at: None,
                    giving_partner: Some(cp.payer_id.clone()),
                    receiving_partner: Some(cp.receiver_id.clone()),
                }
            }
            Some(Contract::RevenueShare(rs)) => {
                let participant_ids: Vec<String> = rs.parties.iter()
                    .map(|p| p.participant_id.clone())
                    .collect();
                ContractInfo {
                    id: rs.id.clone(),
                    contract_type: "Revenue Share".to_string(),
                    description: format!("Revenue Share: {} parties for {}", 
                        rs.parties.len(),
                        rs.transaction_type),
                    participants: participant_ids,
                    next_execution: None,
                    created_at: None,
                    giving_partner: None,
                    receiving_partner: None,
                }
            }
            None => ContractInfo {
                id: "unknown".to_string(),
                contract_type: "Unknown".to_string(),
                description: "Unknown contract type".to_string(),
                participants: vec![],
                next_execution: None,
                created_at: None,
                giving_partner: None,
                receiving_partner: None,
            }
        }
    }

    pub async fn load_smart_contracts(&mut self) -> Result<()> {
        self.loading = true;
        match self.client.list_contracts(None, None, None, Some(100)).await {
            Ok(contracts) => {
                self.smart_contracts = contracts
                    .iter()
                    .map(|contract_resp| Self::contract_response_to_info(contract_resp))
                    .collect();
                // Clear any previous error messages on success
                if let Some(ref msg) = self.status_message {
                    if msg.contains("Failed to load contracts") {
                        self.status_message = None;
                    }
                }
                self.loading = false;
                Ok(())
            }
            Err(e) => {
                self.loading = false;
                // Store error in status message for debugging
                self.status_message = Some(format!("Failed to load contracts: {}", e));
                // Still set empty vector so UI doesn't crash
                self.smart_contracts = Vec::new();
                Err(e)
            }
        }
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
            View::SmartContracts => {
                self.breadcrumb.push(BreadcrumbSegment {
                    label: "Smart Contracts".to_string(),
                    view: View::SmartContracts,
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
            View::CreateContract => {
                self.breadcrumb.push(BreadcrumbSegment {
                    label: "Create Contract".to_string(),
                    view: View::CreateContract,
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
        } else if self.current_view == View::CreateContract {
            if let ContractFormStep::FillVariables = self.contract_form.step {
                if let Some((var_name, ref mut value)) = self.contract_form.variables
                    .get_mut(self.contract_form.selected_variable_index) {
                    value.push(c);
                    // Show account suggestions if this is an account field
                    if Self::is_account_field(var_name) {
                        self.contract_form.account_suggestion_index = None;
                        self.contract_form.show_account_suggestions = true;
                    }
                    // Clear error when user starts typing
                    if let Some(ref err) = self.contract_form.error {
                        if err.contains(var_name.as_str()) {
                            self.contract_form.error = None;
                        }
                    }
                }
            }
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
        } else if self.current_view == View::CreateContract {
            if let ContractFormStep::FillVariables = self.contract_form.step {
                if let Some((var_name, ref mut value)) = self.contract_form.variables
                    .get_mut(self.contract_form.selected_variable_index) {
                    value.pop();
                    // Update account suggestions if this is an account field
                    if Self::is_account_field(var_name) {
                        self.contract_form.account_suggestion_index = None;
                        self.contract_form.show_account_suggestions = true;
                    }
                }
            }
        }
    }
    
    /// Get a suggested value for timestamp variables (human-readable format)
    pub fn get_timestamp_suggestion(&self) -> String {
        Self::get_current_timestamp()
    }
    
    /// Get current timestamp as string (human-readable format)
    fn get_current_timestamp() -> String {
        use chrono::Local;
        let now = Local::now();
        now.format("%Y-%m-%d %H:%M:%S").to_string()
    }
    
    /// Get current timestamp in milliseconds (for internal use)
    fn get_current_timestamp_ms() -> i64 {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64
    }
    
    /// Check if a variable name looks like an account field
    pub fn is_account_field(var_name: &str) -> bool {
        let name_lower = var_name.to_lowercase();
        name_lower.contains("account") || 
        name_lower.contains("_id") && (
            name_lower.contains("from") || 
            name_lower.contains("to") ||
            name_lower.contains("supplier") ||
            name_lower.contains("buyer") ||
            name_lower.contains("provider") ||
            name_lower.contains("subscriber") ||
            name_lower.contains("payer") ||
            name_lower.contains("receiver") ||
            name_lower.contains("lender") ||
            name_lower.contains("borrower")
        )
    }
    
    /// Get account suggestions for the current variable field
    pub fn get_account_suggestions_for_contract(&self) -> Vec<&AccountInfo> {
        if let Some((var_name, var_value)) = self.contract_form.variables.get(self.contract_form.selected_variable_index) {
            if Self::is_account_field(var_name) {
                let filter_lower = var_value.to_lowercase();
                return self.accounts
                    .iter()
                    .filter(|acc| {
                        filter_lower.is_empty() ||
                        acc.id.to_lowercase().contains(&filter_lower) ||
                        acc.account_type.to_lowercase().contains(&filter_lower) ||
                        acc.participant_id.to_lowercase().contains(&filter_lower)
                    })
                    .collect();
            }
        }
        vec![]
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
        if self.current_view == View::Transfer {
            let suggestions = self.get_account_suggestions();
            let current_field_value = match self.transfer_form.selected_field {
                0 => &self.transfer_form.from_account,
                1 => &self.transfer_form.to_account,
                _ => return,
            };
            
            // If there's a currently selected suggestion, use it
            if let Some(suggestion_idx) = self.transfer_form.suggestion_index {
                if let Some(account) = suggestions.get(suggestion_idx) {
                    match self.transfer_form.selected_field {
                        0 => self.transfer_form.from_account = account.id.clone(),
                        1 => self.transfer_form.to_account = account.id.clone(),
                        _ => {}
                    }
                }
            } else if !current_field_value.is_empty() {
                // Try to find an exact match from suggestions
                let filter_lower = current_field_value.to_lowercase();
                if let Some(matched_account) = suggestions.iter().find(|acc| {
                    acc.id.to_lowercase() == filter_lower || 
                    acc.id.to_lowercase().starts_with(&filter_lower)
                }) {
                    match self.transfer_form.selected_field {
                        0 => self.transfer_form.from_account = matched_account.id.clone(),
                        1 => self.transfer_form.to_account = matched_account.id.clone(),
                        _ => {}
                    }
                }
            }
            
            self.transfer_form.suggestion_index = None;
            self.transfer_form.show_suggestions = false;
            // Move to next field
            self.transfer_form.selected_field = (self.transfer_form.selected_field + 1) % 4;
        } else if self.current_view == View::CreateContract {
            self.contract_form.account_suggestion_index = None;
            self.contract_form.show_account_suggestions = false;
            // Move to next variable
            if self.contract_form.selected_variable_index < self.contract_form.variables.len().saturating_sub(1) {
                self.contract_form.selected_variable_index += 1;
            }
        }
    }

    // Contract creation methods

    /// Load available contract templates from examples/contracts directory
    pub fn load_contract_templates(&mut self) -> Result<()> {
        use std::fs;
        use std::path::PathBuf;
        
        // Try to find the project root by searching upward from current directory
        // Look for examples/contracts directory or mix.exs (project root marker)
        let mut current_dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        let mut templates_dir = None;
        
        // Search up to 5 levels up
        for _ in 0..5 {
            let examples_path = current_dir.join("examples/contracts");
            
            // Check if examples/contracts exists at this level
            if examples_path.exists() && examples_path.is_dir() {
                templates_dir = Some(examples_path);
                break;
            }
            
            // Move up one directory
            if let Some(parent) = current_dir.parent() {
                current_dir = parent.to_path_buf();
            } else {
                break;
            }
        }
        
        // Fallback: try relative path from current directory
        let templates_dir = match templates_dir {
            Some(dir) => dir,
            None => {
                // Last resort: try relative path
                PathBuf::from("examples/contracts")
            }
        };
        
        if !templates_dir.exists() {
            let current_dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            let error_msg = format!(
                "Templates directory not found.\nSearched from: {}\nExpected: {}",
                current_dir.display(),
                templates_dir.display()
            );
            self.contract_form.error = Some(error_msg);
            return Ok(());
        }

        let mut templates = Vec::new();
        
        match fs::read_dir(&templates_dir) {
            Ok(entries) => {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.extension().map_or(false, |ext| ext == "yaml" || ext == "yml") {
                        if let Some(file_name) = path.file_stem().and_then(|s| s.to_str()) {
                            // Read first few lines to get description
                            let description = match fs::read_to_string(&path) {
                                Ok(content) => {
                                    // Extract description from YAML comment or name field
                                    content.lines()
                                        .find(|line| line.trim().starts_with("description:"))
                                        .and_then(|line| {
                                            line.splitn(2, ':')
                                                .nth(1)
                                                .map(|s| s.trim().trim_matches('"').trim_matches('\'').to_string())
                                        })
                                        .unwrap_or_else(|| {
                                            // Fallback to first comment line
                                            content.lines()
                                                .find(|line| line.trim().starts_with('#'))
                                                .map(|line| line.trim_start_matches('#').trim().to_string())
                                                .unwrap_or_else(|| format!("{} contract", file_name))
                                        })
                                }
                                Err(e) => {
                                    // If we can't read the file, still add it but with an error note
                                    format!("{} contract (read error: {})", file_name, e)
                                }
                            };

                            templates.push(ContractTemplate {
                                name: file_name.replace('_', " ").to_string(),
                                path: path.to_string_lossy().to_string(),
                                description,
                            });
                        }
                    }
                }
            }
            Err(e) => {
                self.contract_form.error = Some(format!(
                    "Failed to read templates directory: {}\nPath: {}",
                    e,
                    templates_dir.display()
                ));
                return Ok(());
            }
        }

        templates.sort_by(|a, b| a.name.cmp(&b.name));
        self.contract_form.templates = templates;
        
        // Clear error if we successfully loaded templates
        if !self.contract_form.templates.is_empty() {
            self.contract_form.error = None;
        } else if self.contract_form.error.is_none() {
            // Only set generic error if no specific error was set
            self.contract_form.error = Some("No YAML templates found in examples/contracts/".to_string());
        }
        
        Ok(())
    }

    /// Extract variables from YAML content using regex
    pub fn extract_variables_from_yaml(yaml_content: &str) -> Vec<String> {
        use regex::Regex;
        
        // Match ${variable_name} patterns
        let re = Regex::new(r"\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}").unwrap();
        let mut variables = std::collections::HashSet::new();
        
        for cap in re.captures_iter(yaml_content) {
            if let Some(var_name) = cap.get(1) {
                variables.insert(var_name.as_str().to_string());
            }
        }
        
        let mut var_vec: Vec<String> = variables.into_iter().collect();
        var_vec.sort();
        var_vec
    }

    /// Load selected template and extract variables
    pub fn select_template(&mut self, index: usize) -> Result<()> {
        if index >= self.contract_form.templates.len() {
            return Ok(());
        }

        let template = &self.contract_form.templates[index];
        
        match std::fs::read_to_string(&template.path) {
            Ok(content) => {
                self.contract_form.template_content = Some(content.clone());
                self.contract_form.selected_template_index = Some(index);
                
                // Extract variables
                let variable_names = Self::extract_variables_from_yaml(&content);
                let current_timestamp = Self::get_current_timestamp();
                
                // Set smart defaults for variables
                self.contract_form.variables = variable_names
                    .into_iter()
                    .map(|name| {
                        let default_value = if name == "created_at" {
                            // Default to current date/time for created_at
                            current_timestamp.clone()
                        } else if name == "expires_at" {
                            // Default to tomorrow for expires_at
                            use chrono::Local;
                            let tomorrow = Local::now() + chrono::Duration::days(1);
                            tomorrow.format("%Y-%m-%d %H:%M:%S").to_string()
                        } else {
                            String::new()
                        };
                        (name, default_value)
                    })
                    .collect();
                self.contract_form.selected_variable_index = 0;
                self.contract_form.step = ContractFormStep::FillVariables;
                self.contract_form.error = None;
                // Load accounts for account field suggestions
                let _ = self.load_accounts();
                // Check if first variable is an account field
                if let Some((var_name, _)) = self.contract_form.variables.first() {
                    if Self::is_account_field(var_name) {
                        self.contract_form.show_account_suggestions = true;
                    }
                }
                Ok(())
            }
            Err(e) => {
                self.contract_form.error = Some(format!("Failed to read template: {}", e));
                Err(anyhow::anyhow!("Failed to read template: {}", e))
            }
        }
    }

    /// Create contract from filled form
    pub async fn create_contract(&mut self) -> Result<()> {
        self.contract_form.error = None;
        self.contract_form.success = None;

        let template_content = match &self.contract_form.template_content {
            Some(content) => content.clone(),
            None => {
                self.contract_form.error = Some("No template selected".to_string());
                return Ok(());
            }
        };

        // Validate all variables before building the map
        for (var_name, var_value) in &self.contract_form.variables {
            if var_value.trim().is_empty() {
                self.contract_form.error = Some(format!("Variable '{}' is required", var_name));
                return Ok(());
            }
            
            let var_type = VariableType::detect(var_name);
            if let Err(err_msg) = var_type.validate(var_value) {
                self.contract_form.error = Some(format!("Invalid value for '{}': {}", var_name, err_msg));
                return Ok(());
            }
        }

        // Build variables map with validated values
        let mut variables_map = std::collections::HashMap::new();
        for (var_name, var_value) in &self.contract_form.variables {
            // Values are already validated, so we can safely use them
            variables_map.insert(var_name.clone(), var_value.trim().to_string());
        }

        // Call gRPC to create contract
        match self.client.create_generic_contract(&template_content, &variables_map).await {
            Ok(contract) => {
                self.contract_form.success = Some(format!("Contract created: {} ({})", contract.name, contract.id));
                // Reset form
                self.contract_form = ContractForm::default();
                // Reload contracts list
                let _ = self.load_smart_contracts().await;
                Ok(())
            }
            Err(e) => {
                self.contract_form.error = Some(format!("Failed to create contract: {}", e));
                Err(e)
            }
        }
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
    let _ = app.load_smart_contracts().await;
    let _ = app.load_contract_templates();

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
                            } else if app.current_view == View::CreateContract {
                                match app.contract_form.step {
                                    ContractFormStep::SelectTemplate => {
                                        app.running = false;
                                    }
                                    ContractFormStep::FillVariables => {
                                        // Go back to template selection
                                        app.contract_form.step = ContractFormStep::SelectTemplate;
                                        app.contract_form.template_content = None;
                                        app.contract_form.variables.clear();
                                        app.contract_form.selected_variable_index = 0;
                                    }
                                }
                            } else {
                                app.running = false;
                            }
                        }
                        // Tab navigation - in Transfer form and CreateContract, Tab cycles through account suggestions
                        KeyCode::Tab => {
                            if app.current_view == View::Transfer
                                && app.transfer_form.selected_field <= 1
                            {
                                app.next_suggestion();
                            } else if app.current_view == View::CreateContract
                                && app.contract_form.show_account_suggestions
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
                            } else if app.current_view == View::CreateContract
                                && app.contract_form.show_account_suggestions
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
                            } else if app.current_view == View::SmartContracts {
                                let _ = app.load_smart_contracts().await;
                            } else if app.current_view == View::CreateContract {
                                let _ = app.load_contract_templates();
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
                            } else if app.current_view == View::SmartContracts {
                                let _ = app.load_smart_contracts().await;
                            } else if app.current_view == View::CreateContract {
                                let _ = app.load_contract_templates();
                            }
                        }
                        // Ctrl+Number keys for direct tab access
                        KeyCode::Char('1') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            app.goto_view(0);
                        }
                        KeyCode::Char('2') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            app.goto_view(1);
                            let _ = app.load_smart_contracts().await;
                        }
                        KeyCode::Char('3') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            // Entering Transfer view - load all accounts
                            app.goto_view(2);
                            let _ = app.load_accounts().await;
                        }
                        KeyCode::Char('4') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            app.goto_view(3);
                        }
                        KeyCode::Char('5') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            app.goto_view(4);
                            let _ = app.load_future_events().await;
                        }
                        KeyCode::Char('6') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            app.goto_view(5);
                            let _ = app.load_contract_templates();
                        }
                        // List navigation
                        KeyCode::Down | KeyCode::Char('j') => {
                            if app.current_view == View::CreateContract {
                                match app.contract_form.step {
                                    ContractFormStep::SelectTemplate => {
                                        if let Some(idx) = app.contract_form.selected_template_index {
                                            if idx < app.contract_form.templates.len().saturating_sub(1) {
                                                app.contract_form.selected_template_index = Some(idx + 1);
                                            }
                                        } else if !app.contract_form.templates.is_empty() {
                                            app.contract_form.selected_template_index = Some(0);
                                        }
                                    }
                                    ContractFormStep::FillVariables => {
                                        if app.contract_form.selected_variable_index < app.contract_form.variables.len().saturating_sub(1) {
                                            app.contract_form.selected_variable_index += 1;
                                        }
                                    }
                                }
                            } else {
                                app.select_next();
                            }
                        }
                        KeyCode::Up | KeyCode::Char('k') => {
                            if app.current_view == View::CreateContract {
                                match app.contract_form.step {
                                    ContractFormStep::SelectTemplate => {
                                        if let Some(idx) = app.contract_form.selected_template_index {
                                            if idx > 0 {
                                                app.contract_form.selected_template_index = Some(idx - 1);
                                            }
                                        }
                                    }
                                    ContractFormStep::FillVariables => {
                                        if app.contract_form.selected_variable_index > 0 {
                                            app.contract_form.selected_variable_index -= 1;
                                        }
                                    }
                                }
                            } else {
                                app.select_prev();
                            }
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
                            } else if app.current_view == View::CreateContract {
                                match app.contract_form.step {
                                    ContractFormStep::SelectTemplate => {
                                        if let Some(idx) = app.contract_form.selected_template_index {
                                            let _ = app.select_template(idx);
                                        }
                                    }
                                    ContractFormStep::FillVariables => {
                                        // If showing account suggestions, accept current suggestion
                                        if app.contract_form.show_account_suggestions {
                                            app.accept_suggestion();
                                        } else {
                                            // Check if all variables are filled
                                            let all_filled = app.contract_form.variables.iter().all(|(_, v)| !v.trim().is_empty());
                                            if all_filled {
                                                // Create contract
                                                let _ = app.create_contract().await;
                                            } else {
                                                // Move to next empty field
                                                let next_empty = app.contract_form.variables
                                                    .iter()
                                                    .enumerate()
                                                    .find(|(_, (_, v))| v.trim().is_empty())
                                                    .map(|(i, _)| i);
                                                if let Some(next) = next_empty {
                                                    app.contract_form.selected_variable_index = next;
                                                    // Load accounts if entering an account field
                                                    let var_name = &app.contract_form.variables[next].0;
                                                    if App::is_account_field(var_name) {
                                                        let _ = app.load_accounts().await;
                                                        app.contract_form.show_account_suggestions = true;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // Refresh (Ctrl-R)
                        KeyCode::Char('r') if key.modifiers.contains(KeyModifiers::CONTROL) && app.current_view != View::Transfer => {
                            if app.current_view == View::CreateContract {
                                let _ = app.load_contract_templates();
                            } else {
                                let _ = app.load_participants().await;
                                let _ = app.load_accounts().await;
                                let _ = app.load_transactions().await;
                                let _ = app.load_future_events().await;
                                let _ = app.load_smart_contracts().await;
                                // Reload participant detail if viewing it
                                if app.current_view == View::ParticipantDetail {
                                    let participant_id = app.participant_detail.as_ref().map(|d| d.info.id.clone());
                                    if let Some(pid) = participant_id {
                                        let _ = app.load_participant_detail(&pid).await;
                                    }
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
                            } else if app.current_view == View::SmartContracts {
                                let _ = app.load_smart_contracts().await;
                            }
                        }
                        // Text input for Transfer form and CreateContract view
                        KeyCode::Char(c) => {
                            if app.current_view == View::CreateContract {
                                if let ContractFormStep::FillVariables = app.contract_form.step {
                                    // Special handling for 't' key to insert current timestamp
                                    if c == 't' {
                                        let var_name = app.contract_form.variables[app.contract_form.selected_variable_index].0.clone();
                                        let var_type = VariableType::detect(&var_name);
                                        if var_type == VariableType::Timestamp {
                                            let timestamp = app.get_timestamp_suggestion();
                                            if let Some((_, ref mut value)) = app.contract_form.variables
                                                .get_mut(app.contract_form.selected_variable_index) {
                                                *value = timestamp;
                                                // Clear any error
                                                app.contract_form.error = None;
                                            }
                                        } else {
                                            // Regular character input
                                            app.handle_char(c);
                                        }
                                    } else {
                                        app.handle_char(c);
                                    }
                                } else {
                                    app.handle_char(c);
                                }
                            } else {
                                app.handle_char(c);
                            }
                        }
                        KeyCode::Backspace => {
                            if app.current_view == View::CreateContract {
                                if let ContractFormStep::FillVariables = app.contract_form.step {
                                    if let Some((_, ref mut value)) = app.contract_form.variables
                                        .get_mut(app.contract_form.selected_variable_index) {
                                        value.pop();
                                    }
                                } else {
                                    app.handle_backspace();
                                }
                            } else {
                                app.handle_backspace();
                            }
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
