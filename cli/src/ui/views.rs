//! UI Rendering Functions
//!
//! This module contains all the rendering functions for the Scalegraph CLI TUI.
//! It handles the visual presentation of:
//!
//! - Participants list with services
//! - Accounts table with balances
//! - Transfer form with account suggestions
//! - Transaction history
//! - Status bar and navigation tabs
//!
//! All rendering functions use the `ratatui` library to create the terminal UI.
//! The functions are organized by view type and handle layout, styling, and
//! user interaction feedback.

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
            Constraint::Length(1), // Breadcrumb
            Constraint::Min(0),    // Main content
            Constraint::Length(3), // Status bar
        ])
        .split(f.area());

    draw_tabs(f, app, chunks[0]);
    draw_breadcrumb(f, app, chunks[1]);
    draw_main(f, app, chunks[2]);
    draw_status_bar(f, app, chunks[3]);
}

fn draw_tabs(f: &mut Frame, app: &App, area: Rect) {
    let titles: Vec<Line> = View::all()
        .iter()
        .enumerate()
        .map(|(i, v)| {
            let num = format!("[{}] ", i + 1);
            let style = if *v == app.current_view {
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD)
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
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" Scalegraph Ledger  [←/→ or 1-4 to switch tabs] "),
        )
        .highlight_style(Style::default().fg(Color::Yellow))
        .select(
            View::all()
                .iter()
                .position(|v| *v == app.current_view)
                .unwrap_or(0),
        );

    f.render_widget(tabs, area);
}

fn draw_breadcrumb(f: &mut Frame, app: &App, area: Rect) {
    if app.breadcrumb.is_empty() {
        return;
    }

    let mut spans = Vec::new();

    for (i, segment) in app.breadcrumb.iter().enumerate() {
        if i > 0 {
            spans.push(Span::styled(" > ", Style::default().fg(Color::DarkGray)));
        }

        let style = if i == app.breadcrumb.len() - 1 {
            // Current segment - highlighted
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD)
        } else {
            // Previous segments - navigable
            Style::default().fg(Color::Cyan)
        };

        spans.push(Span::styled(segment.label.clone(), style));
    }

    let line = Line::from(spans);
    let paragraph = Paragraph::new(line).block(
        Block::default()
            .borders(Borders::BOTTOM)
            .border_style(Style::default().fg(Color::DarkGray)),
    );

    f.render_widget(paragraph, area);
}

fn draw_main(f: &mut Frame, app: &mut App, area: Rect) {
    match app.current_view {
        View::Participants => draw_participants(f, app, area),
        View::ParticipantDetail => draw_participant_detail(f, app, area),
        View::Accounts => draw_accounts(f, app, area),
        View::Transfer => draw_transfer(f, app, area),
        View::History => draw_history(f, app, area),
    }
}

fn draw_participants(f: &mut Frame, app: &mut App, area: Rect) {
    let selected_idx = app.participant_state.selected().unwrap_or(0);
    let total = app.participants.len();

    let title = format!(" Participants ({}/{}) ", selected_idx + 1, total);

    let header = Row::new(vec![
        Cell::from("Name").style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
        Cell::from("Role").style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
        Cell::from("ID").style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
        Cell::from("Services").style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
    ])
    .height(1)
    .bottom_margin(1);

    let rows: Vec<Row> = app
        .participants
        .iter()
        .enumerate()
        .map(|(i, p)| {
            let selected = app.participant_state.selected() == Some(i);
            let row_style = if selected {
                Style::default().bg(Color::Blue).fg(Color::White)
            } else {
                Style::default()
            };

            // Format services: show first 2, or count if more
            let services_display = if p.services.is_empty() {
                String::from("—")
            } else if p.services.len() <= 2 {
                p.services.join(", ")
            } else {
                format!("{} (+{} more)", p.services[..2].join(", "), p.services.len() - 2)
            };

            // Truncate long names/IDs for better column alignment
            let name_display = if p.name.len() > 25 {
                format!("{}...", &p.name[..22])
            } else {
                p.name.clone()
            };

            let id_display = if p.id.len() > 20 {
                format!("{}...", &p.id[..17])
            } else {
                p.id.clone()
            };

            let prefix = if selected { "▶ " } else { "  " };
            
            Row::new(vec![
                Cell::from(format!("{}{}", prefix, name_display))
                    .style(if selected {
                        Style::default().fg(Color::White).add_modifier(Modifier::BOLD)
                    } else {
                        Style::default().fg(Color::White).add_modifier(Modifier::BOLD)
                    }),
                Cell::from(p.role.clone())
                    .style(if selected {
                        Style::default().fg(Color::White)
                    } else {
                        Style::default().fg(Color::Cyan)
                    }),
                Cell::from(id_display)
                    .style(if selected {
                        Style::default().fg(Color::White)
                    } else {
                        Style::default().fg(Color::DarkGray)
                    }),
                Cell::from(services_display)
                    .style(if selected {
                        Style::default().fg(Color::White)
                    } else {
                        Style::default().fg(Color::Green)
                    }),
            ])
            .style(row_style)
        })
        .collect();

    let widths = [
        Constraint::Percentage(30), // Name
        Constraint::Percentage(20), // Role
        Constraint::Percentage(25), // ID
        Constraint::Percentage(25), // Services
    ];

    let table = Table::new(rows, widths)
        .header(header)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Yellow))
                .title(title),
        );

    f.render_widget(table, area);
    
    // Handle selection navigation manually since Table doesn't support stateful rendering
    // The selection highlighting is already applied in the row styles above
}

fn draw_participant_detail(f: &mut Frame, app: &App, area: Rect) {
    let detail = match &app.participant_detail {
        Some(d) => d,
        None => {
            let msg = Paragraph::new(Line::from(Span::styled(
                "No participant selected",
                Style::default().fg(Color::DarkGray),
            )));
            f.render_widget(msg, area);
            return;
        }
    };

    // Split into left (About/Contact) and right (Accounts summary) columns
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(60), Constraint::Percentage(40)])
        .split(area);

    // Left side: About and Contact sections
    let left_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(8), // About section
            Constraint::Min(0),   // Contact section
        ])
        .split(chunks[0]);

    // About Section
    let created_at_str = if let Some(timestamp) = detail.info.created_at {
        // Convert milliseconds since epoch to readable date
        if let Some(datetime) = chrono::DateTime::from_timestamp_millis(timestamp) {
            datetime.format("%Y-%m-%d %H:%M:%S").to_string()
        } else {
            format!("{}", timestamp)
        }
    } else {
        "Unknown".to_string()
    };
    
    let mut about_lines = vec![
        Line::from(vec![
            Span::styled("Name: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(&detail.info.name, Style::default().fg(Color::White)),
        ]),
        Line::from(vec![
            Span::styled("ID: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(&detail.info.id, Style::default().fg(Color::DarkGray)),
        ]),
        Line::from(vec![
            Span::styled("Role: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(&detail.info.role, Style::default().fg(Color::Cyan)),
        ]),
        Line::from(vec![
            Span::styled("Created: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(&created_at_str, Style::default().fg(Color::DarkGray)),
        ]),
        Line::from(vec![
            Span::styled("Services: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(
                if detail.info.services.is_empty() {
                    "None".to_string()
                } else {
                    detail.info.services.join(", ")
                },
                Style::default().fg(Color::Green),
            ),
        ]),
    ];
    
    // Add About text if available
    if !detail.info.about.is_empty() {
        about_lines.push(Line::raw(""));
        about_lines.push(Line::from(Span::styled(
            "About:",
            Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
        )));
        // Split about text into multiple lines (simple word wrap at 40 chars)
        let about_text = &detail.info.about;
        let words: Vec<&str> = about_text.split_whitespace().collect();
        let mut current_line = String::new();
        for word in words {
            if current_line.len() + word.len() + 1 > 40 && !current_line.is_empty() {
                about_lines.push(Line::from(Span::styled(
                    current_line.clone(),
                    Style::default().fg(Color::White),
                )));
                current_line = word.to_string();
            } else {
                if !current_line.is_empty() {
                    current_line.push(' ');
                }
                current_line.push_str(word);
            }
        }
        if !current_line.is_empty() {
            about_lines.push(Line::from(Span::styled(
                current_line,
                Style::default().fg(Color::White),
            )));
        }
    }

    let about = Paragraph::new(about_lines)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Yellow))
                .title(" About "),
        );
    f.render_widget(about, left_chunks[0]);

    // Contact Section - use structured contact info
    let mut contact_lines = Vec::new();
    let contact = &detail.info.contact;
    
    // Display contact fields that have values
    if !contact.email.is_empty() {
        contact_lines.push(Line::from(vec![
            Span::styled("Email: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(&contact.email, Style::default().fg(Color::White)),
        ]));
    }
    
    if !contact.phone.is_empty() {
        contact_lines.push(Line::from(vec![
            Span::styled("Phone: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(&contact.phone, Style::default().fg(Color::White)),
        ]));
    }
    
    if !contact.website.is_empty() {
        contact_lines.push(Line::from(vec![
            Span::styled("Website: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(&contact.website, Style::default().fg(Color::White)),
        ]));
    }
    
    if !contact.address.is_empty() {
        contact_lines.push(Line::from(vec![
            Span::styled("Address: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(&contact.address, Style::default().fg(Color::White)),
        ]));
    }
    
    // Combine city, postal_code, country into one line if available
    let mut location_parts = Vec::new();
    if !contact.city.is_empty() {
        location_parts.push(contact.city.clone());
    }
    if !contact.postal_code.is_empty() {
        location_parts.push(contact.postal_code.clone());
    }
    if !contact.country.is_empty() {
        location_parts.push(contact.country.clone());
    }
    
    if !location_parts.is_empty() {
        contact_lines.push(Line::from(vec![
            Span::styled("Location: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(location_parts.join(", "), Style::default().fg(Color::White)),
        ]));
    }
    
    // Fall back to metadata if no structured contact info
    if contact_lines.is_empty() {
        let contact_keys = ["email", "phone", "website", "address"];
        for key in &contact_keys {
            if let Some(value) = detail.info.metadata.get(*key) {
                let label = key.chars().next().unwrap().to_uppercase().collect::<String>()
                    + &key[1..].replace("_", " ");
                contact_lines.push(Line::from(vec![
                    Span::styled(
                        format!("{}: ", label),
                        Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
                    ),
                    Span::styled(value, Style::default().fg(Color::White)),
                ]));
            }
        }
    }

    // Add any other metadata entries that aren't standard contact fields
    let contact_keys = ["email", "phone", "website", "address", "contact"];
    for (key, value) in &detail.info.metadata {
        if !contact_keys.contains(&key.as_str()) {
            contact_lines.push(Line::from(vec![
                Span::styled(
                    format!("{}: ", key),
                    Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
                ),
                Span::styled(value, Style::default().fg(Color::White)),
            ]));
        }
    }

    if contact_lines.is_empty() {
        contact_lines.push(Line::from(Span::styled(
            "No contact information available",
            Style::default().fg(Color::DarkGray),
        )));
    }

    let contact = Paragraph::new(contact_lines)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan))
                .title(" Contact "),
        );
    f.render_widget(contact, left_chunks[1]);

    // Right side: Accounts Summary
    let account_summary_lines = vec![
        Line::from(vec![
            Span::styled("Total Balance: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(
                grpc::format_balance(detail.total_balance),
                Style::default().fg(if detail.total_balance >= 0 {
                    Color::Green
                } else {
                    Color::Red
                }),
            ),
        ]),
        Line::from(vec![
            Span::styled("Account Count: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(
                detail.accounts.len().to_string(),
                Style::default().fg(Color::White),
            ),
        ]),
        Line::raw(""),
        Line::from(Span::styled(
            "Accounts:",
            Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
        )),
    ];

    let mut account_list_lines: Vec<Line> = detail
        .accounts
        .iter()
        .take(10) // Show first 10 accounts
        .map(|acc| {
            Line::from(vec![
                Span::styled("  • ", Style::default().fg(Color::DarkGray)),
                Span::styled(&acc.account_type, Style::default().fg(Color::Cyan)),
                Span::raw(": "),
                Span::styled(
                    grpc::format_balance(acc.balance),
                    Style::default().fg(if acc.balance >= 0 {
                        Color::Green
                    } else {
                        Color::Red
                    }),
                ),
            ])
        })
        .collect();

    if detail.accounts.len() > 10 {
        account_list_lines.push(Line::from(Span::styled(
            format!("  ... and {} more", detail.accounts.len() - 10),
            Style::default().fg(Color::DarkGray),
        )));
    }

    let mut all_lines = account_summary_lines;
    all_lines.extend(account_list_lines);

    let accounts_summary = Paragraph::new(all_lines)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green))
                .title(" Accounts Summary "),
        );
    f.render_widget(accounts_summary, chunks[1]);
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
        Cell::from("Account ID").style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
        Cell::from("Type").style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
        Cell::from("Balance").style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
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
                Cell::from(acc.account_type.clone()).style(Style::default().fg(if selected {
                    Color::White
                } else {
                    Color::Cyan
                })),
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

    let table = Table::new(rows, widths).header(header).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Yellow))
            .title(title),
    );

    f.render_widget(table, area);
}

fn draw_transfer(f: &mut Frame, app: &App, area: Rect) {
    // Check if we should show suggestions
    let show_suggestions =
        app.transfer_form.show_suggestions && app.transfer_form.selected_field <= 1;
    let suggestions = if show_suggestions {
        app.get_account_suggestions()
    } else {
        vec![]
    };

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // From
            Constraint::Length(3), // To
            Constraint::Length(3), // Amount
            Constraint::Length(3), // Reference
            Constraint::Length(2), // Submit hint
            Constraint::Min(0),    // Suggestions or Messages
        ])
        .margin(1)
        .split(area);

    let current_field = app.transfer_form.selected_field + 1;
    let title = if show_suggestions && !suggestions.is_empty() {
        format!(
            " Transfer (Field {}/4) - Tab: cycle accounts, Enter: accept ",
            current_field
        )
    } else {
        format!(" Transfer (Field {}/4) ", current_field)
    };
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Yellow))
        .title(title);
    f.render_widget(block, area);

    let fields = [
        (
            "From Account",
            &app.transfer_form.from_account,
            "Tab to browse accounts",
        ),
        (
            "To Account",
            &app.transfer_form.to_account,
            "Tab to browse accounts",
        ),
        (
            "Amount",
            &app.transfer_form.amount,
            "Amount in cents (e.g., 1000 = 10.00)",
        ),
        (
            "Reference",
            &app.transfer_form.reference,
            "Optional reference text",
        ),
    ];

    for (i, (label, value, hint)) in fields.iter().enumerate() {
        let is_selected = app.transfer_form.selected_field == i;

        let (label_style, input_style, border_color) = if is_selected {
            (
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
                Style::default()
                    .fg(Color::White)
                    .add_modifier(Modifier::BOLD),
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

        let paragraph = Paragraph::new(text).block(
            Block::default()
                .borders(Borders::BOTTOM)
                .border_style(Style::default().fg(border_color)),
        );
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
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default().fg(Color::White)
                };
                Line::from(vec![
                    Span::styled(prefix, style),
                    Span::styled(&acc.id, style),
                    Span::styled(" ", Style::default()),
                    Span::styled(
                        format!("[{}]", acc.account_type),
                        Style::default().fg(Color::Cyan),
                    ),
                    Span::styled(" ", Style::default()),
                    Span::styled(
                        grpc::format_balance(acc.balance),
                        Style::default().fg(if acc.balance >= 0 {
                            Color::Green
                        } else {
                            Color::Red
                        }),
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

        let suggestion_widget = Paragraph::new(suggestion_items).block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan))
                .title(title),
        );
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
                " ↑/↓:Select  Enter:View Details  r:Refresh  q:Quit ".to_string()
            }
            View::ParticipantDetail => {
                " Enter:View Accounts  b:Back  q:Quit ".to_string()
            }
            View::Accounts => {
                let back = if app.selected_participant.is_some() {
                    "b:Back  a:Show All  "
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
            View::History => " r:Refresh  q:Quit ".to_string(),
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

    // Right: context-aware info
    let info = match app.current_view {
        View::Participants => {
            format!(" {} participants ", app.participants.len())
        }
        View::ParticipantDetail => {
            if let Some(ref detail) = app.participant_detail {
                format!(" {} accounts | {} total balance ", detail.accounts.len(), grpc::format_balance(detail.total_balance))
            } else {
                " Loading... ".to_string()
            }
        }
        View::Accounts => {
            if let Some(ref pid) = app.selected_participant {
                // Find participant name
                let participant_name = app
                    .participants
                    .iter()
                    .find(|p| p.id == *pid)
                    .map(|p| p.name.clone())
                    .unwrap_or_else(|| pid.clone());
                format!(" {} accounts ({}) ", app.accounts.len(), participant_name)
            } else {
                format!(" {} accounts (all) ", app.accounts.len())
            }
        }
        View::Transfer => {
            // Show available accounts for transfer
            format!(" {} accounts available ", app.accounts.len())
        }
        View::History => {
            format!(" {} transactions ", app.history.len())
        }
    };
    
    let info_widget = Paragraph::new(Line::from(Span::styled(
        info,
        Style::default().fg(Color::DarkGray),
    )))
    .block(Block::default().borders(Borders::ALL).title(" Info "));

    f.render_widget(help, chunks[0]);
    f.render_widget(info_widget, chunks[1]);
}
