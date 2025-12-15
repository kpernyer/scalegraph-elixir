use super::app::{App, View};
use crate::grpc;
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Cell, List, ListItem, Paragraph, Row, Table, Tabs, Wrap},
    Frame,
};

pub fn draw(f: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Tabs
            Constraint::Min(0),    // Main content
            Constraint::Length(3), // Status bar
        ])
        .split(f.area());

    draw_tabs(f, app, chunks[0]);
    draw_main(f, app, chunks[1]);
    draw_status_bar(f, app, chunks[2]);
}

fn draw_tabs(f: &mut Frame, app: &App, area: Rect) {
    let titles: Vec<Line> = View::all()
        .iter()
        .enumerate()
        .map(|(i, v)| {
            let num = format!("[{}] ", i + 1);
            let style = if *v == app.current_view {
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::Gray)
            };
            Line::from(vec![
                Span::styled(num, Style::default().fg(Color::DarkGray)),
                Span::styled(v.title(), style),
            ])
        })
        .collect();

    let tabs = Tabs::new(titles)
        .block(Block::default().borders(Borders::ALL).title(" Scalegraph Ledger  [←/→ or 1-4 to switch tabs] "))
        .highlight_style(Style::default().fg(Color::Yellow))
        .select(View::all().iter().position(|v| *v == app.current_view).unwrap_or(0));

    f.render_widget(tabs, area);
}

fn draw_main(f: &mut Frame, app: &mut App, area: Rect) {
    match app.current_view {
        View::Participants => draw_participants(f, app, area),
        View::Accounts => draw_accounts(f, app, area),
        View::Transfer => draw_transfer(f, app, area),
        View::History => draw_history(f, app, area),
    }
}

fn draw_participants(f: &mut Frame, app: &mut App, area: Rect) {
    let selected_idx = app.participant_state.selected().unwrap_or(0);
    let total = app.participants.len();

    let items: Vec<ListItem> = app
        .participants
        .iter()
        .map(|p| {
            let content = Line::from(vec![
                Span::styled(
                    format!("{:<20}", p.name),
                    Style::default().fg(Color::White).add_modifier(Modifier::BOLD),
                ),
                Span::raw(" "),
                Span::styled(
                    format!("[{}]", p.role),
                    Style::default().fg(Color::Cyan),
                ),
                Span::raw(" "),
                Span::styled(
                    format!("({})", p.id),
                    Style::default().fg(Color::DarkGray),
                ),
            ]);
            ListItem::new(content)
        })
        .collect();

    let title = format!(" Participants ({}/{}) ", selected_idx + 1, total);
    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Yellow))
                .title(title),
        )
        .highlight_style(
            Style::default()
                .bg(Color::Blue)
                .fg(Color::White)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("▶ ");

    f.render_stateful_widget(list, area, &mut app.participant_state);
}

fn draw_accounts(f: &mut Frame, app: &mut App, area: Rect) {
    let selected_idx = app.account_state.selected().unwrap_or(0);
    let total = app.accounts.len();

    let title = if let Some(ref pid) = app.selected_participant {
        format!(" Accounts for {} ({}/{}) ", pid, selected_idx + 1, total)
    } else {
        format!(" All Accounts ({}/{}) ", selected_idx + 1, total)
    };

    let header = Row::new(vec![
        Cell::from("Account ID").style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
        Cell::from("Type").style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
        Cell::from("Balance").style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
    ])
    .height(1)
    .bottom_margin(1);

    let rows: Vec<Row> = app
        .accounts
        .iter()
        .enumerate()
        .map(|(i, acc)| {
            let selected = app.account_state.selected() == Some(i);
            let style = if selected {
                Style::default().bg(Color::Blue).fg(Color::White)
            } else {
                Style::default()
            };

            let balance_color = if selected {
                Color::White
            } else if acc.balance < 0 {
                Color::Red
            } else if acc.balance > 0 {
                Color::Green
            } else {
                Color::White
            };

            let prefix = if selected { "▶ " } else { "  " };
            Row::new(vec![
                Cell::from(format!("{}{}", prefix, acc.id)),
                Cell::from(acc.account_type.clone()).style(Style::default().fg(if selected { Color::White } else { Color::Cyan })),
                Cell::from(grpc::format_balance(acc.balance))
                    .style(Style::default().fg(balance_color)),
            ])
            .style(style)
        })
        .collect();

    let widths = [
        Constraint::Percentage(50),
        Constraint::Percentage(20),
        Constraint::Percentage(30),
    ];

    let table = Table::new(rows, widths)
        .header(header)
        .block(Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Yellow))
            .title(title));

    f.render_widget(table, area);
}

fn draw_transfer(f: &mut Frame, app: &App, area: Rect) {
    // Check if we should show suggestions
    let show_suggestions = app.transfer_form.show_suggestions && app.transfer_form.selected_field <= 1;
    let suggestions = if show_suggestions {
        app.get_account_suggestions()
    } else {
        vec![]
    };

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),  // From
            Constraint::Length(3),  // To
            Constraint::Length(3),  // Amount
            Constraint::Length(3),  // Reference
            Constraint::Length(2),  // Submit hint
            Constraint::Min(0),     // Suggestions or Messages
        ])
        .margin(1)
        .split(area);

    let current_field = app.transfer_form.selected_field + 1;
    let title = if show_suggestions && !suggestions.is_empty() {
        format!(" Transfer (Field {}/4) - Tab: cycle accounts, Enter: accept ", current_field)
    } else {
        format!(" Transfer (Field {}/4) ", current_field)
    };
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Yellow))
        .title(title);
    f.render_widget(block, area);

    let fields = [
        ("From Account", &app.transfer_form.from_account, "Tab to browse accounts"),
        ("To Account", &app.transfer_form.to_account, "Tab to browse accounts"),
        ("Amount", &app.transfer_form.amount, "Amount in cents (e.g., 1000 = 10.00)"),
        ("Reference", &app.transfer_form.reference, "Optional reference text"),
    ];

    for (i, (label, value, hint)) in fields.iter().enumerate() {
        let is_selected = app.transfer_form.selected_field == i;

        let (label_style, input_style, border_color) = if is_selected {
            (
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
                Style::default().fg(Color::White).add_modifier(Modifier::BOLD),
                Color::Yellow,
            )
        } else {
            (
                Style::default().fg(Color::DarkGray),
                Style::default().fg(Color::Gray),
                Color::DarkGray,
            )
        };

        let cursor = if is_selected { "█" } else { "" };
        let display_value = if value.is_empty() && !is_selected {
            format!("({})", hint)
        } else {
            format!("{}{}", value, cursor)
        };

        let indicator = if is_selected { "▶ " } else { "  " };
        let text = Line::from(vec![
            Span::styled(indicator, label_style),
            Span::styled(format!("{}: ", label), label_style),
            Span::styled(display_value, input_style),
        ]);

        let paragraph = Paragraph::new(text)
            .block(Block::default()
                .borders(Borders::BOTTOM)
                .border_style(Style::default().fg(border_color)));
        f.render_widget(paragraph, chunks[i]);
    }

    // Submit hint with context-sensitive key info
    let hint_text = if app.transfer_form.selected_field <= 1 {
        Line::from(vec![
            Span::styled("Tab", Style::default().fg(Color::Cyan)),
            Span::styled("/", Style::default().fg(Color::DarkGray)),
            Span::styled("Shift+Tab", Style::default().fg(Color::Cyan)),
            Span::styled(" Cycle accounts  ", Style::default().fg(Color::DarkGray)),
            Span::styled("Enter", Style::default().fg(Color::Green)),
            Span::styled(" Accept & next  ", Style::default().fg(Color::DarkGray)),
            Span::styled("↑/↓", Style::default().fg(Color::Cyan)),
            Span::styled(" Fields", Style::default().fg(Color::DarkGray)),
        ])
    } else {
        Line::from(vec![
            Span::styled("↑/↓", Style::default().fg(Color::Cyan)),
            Span::styled(" Navigate  ", Style::default().fg(Color::DarkGray)),
            Span::styled("Enter", Style::default().fg(Color::Green)),
            Span::styled(" Execute Transfer  ", Style::default().fg(Color::DarkGray)),
            Span::styled("Esc", Style::default().fg(Color::Red)),
            Span::styled(" Clear", Style::default().fg(Color::DarkGray)),
        ])
    };
    let hint = Paragraph::new(hint_text);
    f.render_widget(hint, chunks[4]);

    // Show suggestions or error/success messages in bottom area
    if show_suggestions && !suggestions.is_empty() {
        // Show account suggestions
        let suggestion_items: Vec<Line> = suggestions
            .iter()
            .enumerate()
            .take(8) // Max 8 suggestions
            .map(|(i, acc)| {
                let is_current = app.transfer_form.suggestion_index == Some(i);
                let prefix = if is_current { "▶ " } else { "  " };
                let style = if is_current {
                    Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
                } else {
                    Style::default().fg(Color::White)
                };
                Line::from(vec![
                    Span::styled(prefix, style),
                    Span::styled(&acc.id, style),
                    Span::styled(" ", Style::default()),
                    Span::styled(format!("[{}]", acc.account_type), Style::default().fg(Color::Cyan)),
                    Span::styled(" ", Style::default()),
                    Span::styled(
                        grpc::format_balance(acc.balance),
                        Style::default().fg(if acc.balance >= 0 { Color::Green } else { Color::Red }),
                    ),
                ])
            })
            .collect();

        let suggestion_count = suggestions.len();
        let title = if suggestion_count > 8 {
            format!(" Accounts ({} shown of {}) ", 8, suggestion_count)
        } else {
            format!(" Accounts ({}) ", suggestion_count)
        };

        let suggestion_widget = Paragraph::new(suggestion_items)
            .block(Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan))
                .title(title));
        f.render_widget(suggestion_widget, chunks[5]);
    } else if let Some(ref err) = app.transfer_form.error {
        let msg = Paragraph::new(Line::from(vec![
            Span::styled("✗ ", Style::default().fg(Color::Red)),
            Span::styled(err.as_str(), Style::default().fg(Color::Red)),
        ]))
        .wrap(Wrap { trim: true });
        f.render_widget(msg, chunks[5]);
    } else if let Some(ref success) = app.transfer_form.success {
        let msg = Paragraph::new(Line::from(vec![
            Span::styled("✓ ", Style::default().fg(Color::Green)),
            Span::styled(success.as_str(), Style::default().fg(Color::Green)),
        ]))
        .wrap(Wrap { trim: true });
        f.render_widget(msg, chunks[5]);
    }
}

fn draw_history(f: &mut Frame, app: &App, area: Rect) {
    let total = app.history.len();

    let items: Vec<ListItem> = if app.history.is_empty() {
        vec![ListItem::new(Line::from(Span::styled(
            "  No transactions yet. Use the Transfer tab to create one.",
            Style::default().fg(Color::DarkGray),
        )))]
    } else {
        app.history
            .iter()
            .rev()
            .enumerate()
            .map(|(i, h)| {
                let num = format!("{:>3}. ", total - i);
                ListItem::new(Line::from(vec![
                    Span::styled(num, Style::default().fg(Color::DarkGray)),
                    Span::styled(h.clone(), Style::default().fg(Color::White)),
                ]))
            })
            .collect()
    };

    let title = format!(" Transaction History ({} total) ", total);
    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Yellow))
            .title(title),
    );

    f.render_widget(list, area);
}

fn draw_status_bar(f: &mut Frame, app: &App, area: Rect) {
    let help_text = if app.loading {
        "Loading...".to_string()
    } else {
        match app.current_view {
            View::Participants => {
                " ↑/↓:Select  Enter:View Accounts  r:Refresh  q:Quit ".to_string()
            }
            View::Accounts => {
                let back = if app.selected_participant.is_some() {
                    "a:Show All  "
                } else {
                    ""
                };
                format!(" ↑/↓:Select  {}r:Refresh  q:Quit ", back)
            }
            View::Transfer => {
                if app.transfer_form.selected_field <= 1 {
                    " Tab:Cycle Accounts  Enter:Accept  ↑/↓:Fields  ←/→:Tabs  q:Quit ".to_string()
                } else {
                    " ↑/↓:Fields  Enter:Execute  Esc:Clear  ←/→:Tabs  q:Quit ".to_string()
                }
            }
            View::History => {
                " r:Refresh  q:Quit ".to_string()
            }
        }
    };

    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(70), Constraint::Percentage(30)])
        .split(area);

    // Left: context-sensitive help
    let help_style = if app.loading {
        Style::default().fg(Color::Yellow)
    } else {
        Style::default().fg(Color::Cyan)
    };
    let help = Paragraph::new(Line::from(Span::styled(help_text, help_style)))
        .block(Block::default().borders(Borders::ALL).title(" Keys "));

    // Right: global info
    let info = format!(" {} participants | {} accounts ", app.participants.len(), app.accounts.len());
    let info_widget = Paragraph::new(Line::from(Span::styled(info, Style::default().fg(Color::DarkGray))))
        .block(Block::default().borders(Borders::ALL).title(" Info "));

    f.render_widget(help, chunks[0]);
    f.render_widget(info_widget, chunks[1]);
}
