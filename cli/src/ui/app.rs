use crate::grpc::{self, ScalegraphClient};
use anyhow::Result;
use crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers};
use ratatui::{backend::CrosstermBackend, widgets::ListState, Terminal};
use std::io::Stdout;

pub type AppResult<T> = Result<T>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum View {
    Participants,
    Accounts,
    Transfer,
    History,
}

impl View {
    pub fn all() -> Vec<View> {
        vec![
            View::Participants,
            View::Accounts,
            View::Transfer,
            View::History,
        ]
    }

    pub fn title(&self) -> &'static str {
        match self {
            View::Participants => "Participants",
            View::Accounts => "Accounts",
            View::Transfer => "Transfer",
            View::History => "History",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ParticipantInfo {
    pub id: String,
    pub name: String,
    pub role: String,
}

#[derive(Debug, Clone)]
pub struct AccountInfo {
    pub id: String,
    #[allow(dead_code)]
    pub participant_id: String,
    pub account_type: String,
    pub balance: i64,
}

#[derive(Debug, Clone)]
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

impl Default for TransferForm {
    fn default() -> Self {
        Self {
            from_account: String::new(),
            to_account: String::new(),
            amount: String::new(),
            reference: String::new(),
            selected_field: 0,
            error: None,
            success: None,
            suggestion_index: None,
            show_suggestions: false,
        }
    }
}

pub struct App {
    pub client: ScalegraphClient,
    pub current_view: View,
    pub running: bool,

    // Participants view
    pub participants: Vec<ParticipantInfo>,
    pub participant_state: ListState,

    // Accounts view
    pub accounts: Vec<AccountInfo>,
    pub account_state: ListState,
    pub selected_participant: Option<String>,

    // Transfer view
    pub transfer_form: TransferForm,

    // History
    pub history: Vec<String>,

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

        Self {
            client,
            current_view: View::Participants,
            running: true,
            participants: Vec::new(),
            participant_state,
            accounts: Vec::new(),
            account_state,
            selected_participant: None,
            transfer_form: TransferForm::default(),
            history: Vec::new(),
            status_message: None,
            loading: false,
        }
    }

    pub async fn load_participants(&mut self) -> Result<()> {
        self.loading = true;
        let participants = self.client.list_participants(None).await?;
        self.participants = participants
            .into_iter()
            .map(|p| ParticipantInfo {
                id: p.id,
                name: p.name,
                role: grpc::role_to_string(p.role).to_string(),
            })
            .collect();
        self.loading = false;
        Ok(())
    }

    pub async fn load_accounts(&mut self, participant_id: Option<&str>) -> Result<()> {
        self.loading = true;
        self.accounts.clear();

        let participant_ids: Vec<String> = if let Some(id) = participant_id {
            vec![id.to_string()]
        } else {
            self.participants.iter().map(|p| p.id.clone()).collect()
        };

        for pid in participant_ids {
            if let Ok(accounts) = self.client.get_participant_accounts(&pid).await {
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

    pub fn next_view(&mut self) {
        let views = View::all();
        let idx = views
            .iter()
            .position(|v| *v == self.current_view)
            .unwrap_or(0);
        self.current_view = views[(idx + 1) % views.len()];
    }

    pub fn prev_view(&mut self) {
        let views = View::all();
        let idx = views
            .iter()
            .position(|v| *v == self.current_view)
            .unwrap_or(0);
        self.current_view = views[(idx + views.len() - 1) % views.len()];
    }

    pub fn goto_view(&mut self, index: usize) {
        let views = View::all();
        if index < views.len() {
            self.current_view = views[index];
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
            View::Accounts => {
                let i = self.account_state.selected().unwrap_or(0);
                if i < self.accounts.len().saturating_sub(1) {
                    self.account_state.select(Some(i + 1));
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
            View::Accounts => {
                let i = self.account_state.selected().unwrap_or(0);
                if i > 0 {
                    self.account_state.select(Some(i - 1));
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
    let _ = app.load_accounts(None).await;
    let _ = app.load_transactions().await;

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
                                // Reload all accounts when entering Transfer view
                                if !was_transfer && app.current_view == View::Transfer {
                                    let _ = app.load_accounts(None).await;
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
                                // Reload all accounts when entering Transfer view
                                if !was_transfer && app.current_view == View::Transfer {
                                    let _ = app.load_accounts(None).await;
                                }
                            }
                        }
                        KeyCode::Right => {
                            // Right arrow always switches to next tab
                            let was_transfer = app.current_view == View::Transfer;
                            app.next_view();
                            // Reload all accounts when entering Transfer view
                            if !was_transfer && app.current_view == View::Transfer {
                                let _ = app.load_accounts(None).await;
                            }
                        }
                        KeyCode::Left => {
                            // Left arrow always switches to previous tab
                            let was_transfer = app.current_view == View::Transfer;
                            app.prev_view();
                            // Reload all accounts when entering Transfer view
                            if !was_transfer && app.current_view == View::Transfer {
                                let _ = app.load_accounts(None).await;
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
                            let _ = app.load_accounts(None).await;
                        }
                        KeyCode::Char('4') if app.current_view != View::Transfer => {
                            app.goto_view(3);
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
                            View::Accounts => app.account_state.select(Some(0)),
                            _ => {}
                        },
                        KeyCode::End => match app.current_view {
                            View::Participants => {
                                let len = app.participants.len();
                                if len > 0 {
                                    app.participant_state.select(Some(len - 1));
                                }
                            }
                            View::Accounts => {
                                let len = app.accounts.len();
                                if len > 0 {
                                    app.account_state.select(Some(len - 1));
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
                                        app.selected_participant = Some(pid.clone());
                                        let _ = app.load_accounts(Some(&pid)).await;
                                        app.current_view = View::Accounts;
                                    }
                                }
                            }
                        }
                        // Refresh
                        KeyCode::Char('r') if app.current_view != View::Transfer => {
                            let _ = app.load_participants().await;
                            let _ = app.load_accounts(None).await;
                            let _ = app.load_transactions().await;
                        }
                        // Show all accounts
                        KeyCode::Char('a') if app.current_view == View::Accounts => {
                            app.selected_participant = None;
                            let _ = app.load_accounts(None).await;
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
