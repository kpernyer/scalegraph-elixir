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

use super::app::{App, ContractFormStep, VariableType, View};
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
                .title(" Scalegraph Ledger  [←/→ or Ctrl+1-6 to switch tabs] "),
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
        View::SmartContracts => draw_smart_contracts(f, app, area),
        View::Transfer => draw_transfer(f, app, area),
        View::History => draw_history(f, app, area),
        View::Future => draw_future(f, app, area),
        View::CreateContract => draw_create_contract(f, app, area),
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

fn draw_smart_contracts(f: &mut Frame, app: &App, area: Rect) {
    // Show loading or error message if applicable
    if app.loading {
        let msg = Paragraph::new(Line::from(Span::styled(
            "Loading contracts...",
            Style::default().fg(Color::Yellow),
        )));
        f.render_widget(msg, area);
        return;
    }
    
    if let Some(ref error_msg) = app.status_message {
        if error_msg.contains("Failed to load contracts") {
            let msg = Paragraph::new(vec![
                Line::from(Span::styled(
                    "Error loading contracts:",
                    Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
                )),
                Line::from(Span::styled(
                    error_msg,
                    Style::default().fg(Color::Red),
                )),
                Line::raw(""),
                Line::from(Span::styled(
                    "Press 'r' to retry",
                    Style::default().fg(Color::DarkGray),
                )),
            ])
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Red))
                    .title(" Error "),
            );
            f.render_widget(msg, area);
            return;
        }
    }
    
    // Split into 2x2 grid
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(area);
    
    let top_row = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(rows[0]);
    
    let bottom_row = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(rows[1]);
    
    // Check if we have any contracts
    if app.smart_contracts.is_empty() {
        let msg = Paragraph::new(vec![
            Line::from(Span::styled(
                "No contracts found",
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
            )),
            Line::raw(""),
            Line::from(Span::styled(
                "The system doesn't have any smart contracts yet.",
                Style::default().fg(Color::DarkGray),
            )),
            Line::raw(""),
            Line::from(Span::styled(
                "Contracts can be created via:",
                Style::default().fg(Color::DarkGray),
            )),
            Line::from(Span::styled(
                "  • gRPC API",
                Style::default().fg(Color::Cyan),
            )),
            Line::from(Span::styled(
                "  • YAML files (mix scalegraph.contract.load)",
                Style::default().fg(Color::Cyan),
            )),
            Line::raw(""),
            Line::from(Span::styled(
                "Press 'r' to refresh",
                Style::default().fg(Color::DarkGray),
            )),
        ])
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Yellow))
                .title(" Smart Contracts "),
        );
        f.render_widget(msg, area);
        return;
    }
    
    // View 1: Latest 5 contracts
    let mut latest = app.smart_contracts.clone();
    latest.sort_by(|a, b| {
        let a_time = a.created_at.unwrap_or(0);
        let b_time = b.created_at.unwrap_or(0);
        b_time.cmp(&a_time) // Descending order
    });
    let latest_5: Vec<_> = latest.into_iter().take(5).collect();
    
    let latest_items: Vec<ListItem> = if latest_5.is_empty() {
        vec![ListItem::new(Line::from(Span::styled(
            "  No contracts available",
            Style::default().fg(Color::DarkGray),
        )))]
    } else {
        latest_5
            .iter()
            .enumerate()
            .map(|(i, contract)| {
                let num = format!("{:>2}. ", i + 1);
                let id_short = if contract.id.len() > 12 {
                    format!("{}...", &contract.id[..9])
                } else {
                    contract.id.clone()
                };
                ListItem::new(vec![
                    Line::from(vec![
                        Span::styled(num, Style::default().fg(Color::DarkGray)),
                        Span::styled(&contract.contract_type, Style::default().fg(Color::Cyan)),
                        Span::raw(" - "),
                        Span::styled(id_short, Style::default().fg(Color::Green)),
                    ]),
                    Line::from(vec![
                        Span::raw("    "),
                        Span::styled(
                            if contract.description.len() > 40 {
                                format!("{}...", &contract.description[..37])
                            } else {
                                contract.description.clone()
                            },
                            Style::default().fg(Color::White),
                        ),
                    ]),
                ])
            })
            .collect()
    };
    
    let latest_list = List::new(latest_items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Yellow))
                .title(format!(" Latest 5 Contracts ({}) ", app.smart_contracts.len())),
        );
    f.render_widget(latest_list, top_row[0]);
    
    // View 2: Sorted by receiving partner
    let mut by_receiving = app.smart_contracts.clone();
    by_receiving.sort_by(|a, b| {
        let a_rec = a.receiving_partner.as_ref().unwrap_or(&String::new()).clone();
        let b_rec = b.receiving_partner.as_ref().unwrap_or(&String::new()).clone();
        a_rec.cmp(&b_rec)
    });
    
    let receiving_items: Vec<ListItem> = if by_receiving.is_empty() {
        vec![ListItem::new(Line::from(Span::styled(
            "  No contracts available",
            Style::default().fg(Color::DarkGray),
        )))]
    } else {
        by_receiving
            .iter()
            .enumerate()
            .map(|(i, contract)| {
                let num = format!("{:>2}. ", i + 1);
                let receiver = contract.receiving_partner.as_ref()
                    .map(|r| if r.len() > 15 { format!("{}...", &r[..12]) } else { r.clone() })
                    .unwrap_or_else(|| "N/A".to_string());
                ListItem::new(vec![
                    Line::from(vec![
                        Span::styled(num, Style::default().fg(Color::DarkGray)),
                        Span::styled("To: ", Style::default().fg(Color::Yellow)),
                        Span::styled(receiver, Style::default().fg(Color::Green)),
                    ]),
                    Line::from(vec![
                        Span::raw("    "),
                        Span::styled(&contract.contract_type, Style::default().fg(Color::Cyan)),
                        Span::raw(" - "),
                        Span::styled(
                            if contract.description.len() > 30 {
                                format!("{}...", &contract.description[..27])
                            } else {
                                contract.description.clone()
                            },
                            Style::default().fg(Color::White),
                        ),
                    ]),
                ])
            })
            .collect()
    };
    
    let receiving_list = List::new(receiving_items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green))
                .title(" By Receiving Partner "),
        );
    f.render_widget(receiving_list, top_row[1]);
    
    // View 3: Sorted by giving partner
    let mut by_giving = app.smart_contracts.clone();
    by_giving.sort_by(|a, b| {
        let a_giv = a.giving_partner.as_ref().unwrap_or(&String::new()).clone();
        let b_giv = b.giving_partner.as_ref().unwrap_or(&String::new()).clone();
        a_giv.cmp(&b_giv)
    });
    
    let giving_items: Vec<ListItem> = if by_giving.is_empty() {
        vec![ListItem::new(Line::from(Span::styled(
            "  No contracts available",
            Style::default().fg(Color::DarkGray),
        )))]
    } else {
        by_giving
            .iter()
            .enumerate()
            .map(|(i, contract)| {
                let num = format!("{:>2}. ", i + 1);
                let giver = contract.giving_partner.as_ref()
                    .map(|g| if g.len() > 15 { format!("{}...", &g[..12]) } else { g.clone() })
                    .unwrap_or_else(|| "N/A".to_string());
                ListItem::new(vec![
                    Line::from(vec![
                        Span::styled(num, Style::default().fg(Color::DarkGray)),
                        Span::styled("From: ", Style::default().fg(Color::Yellow)),
                        Span::styled(giver, Style::default().fg(Color::Magenta)),
                    ]),
                    Line::from(vec![
                        Span::raw("    "),
                        Span::styled(&contract.contract_type, Style::default().fg(Color::Cyan)),
                        Span::raw(" - "),
                        Span::styled(
                            if contract.description.len() > 30 {
                                format!("{}...", &contract.description[..27])
                            } else {
                                contract.description.clone()
                            },
                            Style::default().fg(Color::White),
                        ),
                    ]),
                ])
            })
            .collect()
    };
    
    let giving_list = List::new(giving_items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Magenta))
                .title(" By Giving Partner "),
        );
    f.render_widget(giving_list, bottom_row[0]);
    
    // View 4: All contracts sorted by type
    let mut by_type = app.smart_contracts.clone();
    by_type.sort_by(|a, b| {
        let type_cmp = a.contract_type.cmp(&b.contract_type);
        if type_cmp == std::cmp::Ordering::Equal {
            a.id.cmp(&b.id)
        } else {
            type_cmp
        }
    });
    
    let type_items: Vec<ListItem> = if by_type.is_empty() {
        vec![ListItem::new(Line::from(Span::styled(
            "  No contracts available",
            Style::default().fg(Color::DarkGray),
        )))]
    } else {
        by_type
            .iter()
            .enumerate()
            .map(|(i, contract)| {
                let num = format!("{:>2}. ", i + 1);
                let id_short = if contract.id.len() > 12 {
                    format!("{}...", &contract.id[..9])
                } else {
                    contract.id.clone()
                };
                ListItem::new(vec![
                    Line::from(vec![
                        Span::styled(num, Style::default().fg(Color::DarkGray)),
                        Span::styled(&contract.contract_type, Style::default().fg(Color::Cyan)),
                        Span::raw(" - "),
                        Span::styled(id_short, Style::default().fg(Color::Green)),
                    ]),
                    Line::from(vec![
                        Span::raw("    "),
                        Span::styled(
                            if contract.description.len() > 40 {
                                format!("{}...", &contract.description[..37])
                            } else {
                                contract.description.clone()
                            },
                            Style::default().fg(Color::White),
                        ),
                    ]),
                ])
            })
            .collect()
    };
    
    let type_list = List::new(type_items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Blue))
                .title(" All Contracts (by Type) "),
        );
    f.render_widget(type_list, bottom_row[1]);
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
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
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

    // Right side: Accounts and Contracts
    // Calculate dynamic height for accounts section: header (4 lines) + account list
    let accounts_header_height = 4; // Total Balance, Account Count, blank, "Accounts:" header
    let calculated_height = accounts_header_height + detail.accounts.len() + 1; // +1 for border
    // Cap at 80% of available height to leave room for contracts
    let max_height = (area.height as usize * 4 / 5).max(8); // At least 8 lines
    let accounts_display_height = calculated_height.min(max_height) as u16;
    
    let right_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(accounts_display_height), // Accounts summary (dynamic)
            Constraint::Min(0),   // Contracts
        ])
        .split(chunks[1]);

    // Accounts Summary
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

    // Show all accounts (no limit)
    let account_list_lines: Vec<Line> = detail
        .accounts
        .iter()
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

    let mut all_account_lines = account_summary_lines;
    all_account_lines.extend(account_list_lines);

    let accounts_summary = Paragraph::new(all_account_lines)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green))
                .title(" Accounts "),
        );
    f.render_widget(accounts_summary, right_chunks[0]);

    // Smart Contracts
    let mut contract_lines = vec![
        Line::from(vec![
            Span::styled("Contracts: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(
                detail.contracts.len().to_string(),
                Style::default().fg(Color::White),
            ),
        ]),
        Line::raw(""),
    ];

    if detail.contracts.is_empty() {
        contract_lines.push(Line::from(Span::styled(
            "  No contracts",
            Style::default().fg(Color::DarkGray),
        )));
    } else {
        for contract in detail.contracts.iter().take(10) {
            contract_lines.push(Line::from(vec![
                Span::styled("  • ", Style::default().fg(Color::DarkGray)),
                Span::styled(&contract.contract_type, Style::default().fg(Color::Cyan)),
                Span::raw(": "),
            ]));
            
            // Description on next line if needed
            let desc = if contract.description.len() > 30 {
                format!("{}...", &contract.description[..27])
            } else {
                contract.description.clone()
            };
            contract_lines.push(Line::from(vec![
                Span::raw("    "),
                Span::styled(desc, Style::default().fg(Color::White)),
            ]));
            
            // Show other participants
            if !contract.participants.is_empty() {
                let participants_str = contract.participants.join(", ");
                let participants_display = if participants_str.len() > 30 {
                    format!("{}...", &participants_str[..27])
                } else {
                    participants_str
                };
                contract_lines.push(Line::from(vec![
                    Span::raw("    "),
                    Span::styled("With: ", Style::default().fg(Color::DarkGray)),
                    Span::styled(participants_display, Style::default().fg(Color::Green)),
                ]));
            }
            contract_lines.push(Line::raw(""));
        }
        
        if detail.contracts.len() > 10 {
            contract_lines.push(Line::from(Span::styled(
                format!("  ... and {} more", detail.contracts.len() - 10),
                Style::default().fg(Color::DarkGray),
            )));
        }
    }

    let contracts_widget = Paragraph::new(contract_lines)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Magenta))
                .title(" Smart Contracts "),
        );
    f.render_widget(contracts_widget, right_chunks[1]);
}

fn draw_future(f: &mut Frame, app: &App, area: Rect) {
    let total = app.future_events.len();

    let items: Vec<ListItem> = if app.future_events.is_empty() {
        vec![
            ListItem::new(Line::from(Span::styled(
                "  No scheduled events found.",
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
            ))),
            ListItem::new(Line::raw("")),
            ListItem::new(Line::from(Span::styled(
                "  Contracts need execution dates to appear here:",
                Style::default().fg(Color::DarkGray),
            ))),
            ListItem::new(Line::from(Span::styled(
                "    • expires_at (in conditions or metadata)",
                Style::default().fg(Color::Cyan),
            ))),
            ListItem::new(Line::from(Span::styled(
                "    • due_date (for invoices)",
                Style::default().fg(Color::Cyan),
            ))),
            ListItem::new(Line::from(Span::styled(
                "    • next_billing_date (for subscriptions)",
                Style::default().fg(Color::Cyan),
            ))),
            ListItem::new(Line::from(Span::styled(
                "    • first_payment_date (for recurring payments)",
                Style::default().fg(Color::Cyan),
            ))),
            ListItem::new(Line::raw("")),
            ListItem::new(Line::from(Span::styled(
                "  Press Ctrl-R to refresh",
                Style::default().fg(Color::DarkGray),
            ))),
        ]
    } else {
        app.future_events
            .iter()
            .enumerate()
            .map(|(i, event)| {
                // Format execution time
                let execution_time_str = if let Some(datetime) = chrono::DateTime::from_timestamp_millis(event.execution_time) {
                    datetime.format("%Y-%m-%d %H:%M:%S").to_string()
                } else {
                    format!("{}", event.execution_time)
                };
                
                let num = format!("{:>2}. ", i + 1);
                ListItem::new(vec![
                    Line::from(vec![
                        Span::styled(num, Style::default().fg(Color::DarkGray)),
                        Span::styled(execution_time_str.clone(), Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
                        Span::raw(" - "),
                        Span::styled(event.contract_type.clone(), Style::default().fg(Color::Cyan)),
                    ]),
                    Line::from(vec![
                        Span::raw("    "),
                        Span::styled(event.description.clone(), Style::default().fg(Color::White)),
                    ]),
                    Line::from(vec![
                        Span::raw("    "),
                        Span::styled("Contract: ", Style::default().fg(Color::DarkGray)),
                        Span::styled(event.contract_id.clone(), Style::default().fg(Color::Green)),
                    ]),
                ])
            })
            .collect()
    };

    let title = format!(" Scheduled Events ({} upcoming) ", total);
    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Yellow))
            .title(title),
    );

    f.render_widget(list, area);
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

fn draw_create_contract(f: &mut Frame, app: &App, area: Rect) {
    match app.contract_form.step {
        ContractFormStep::SelectTemplate => draw_template_selection(f, app, area),
        ContractFormStep::FillVariables => draw_variable_input(f, app, area),
    }
}

fn draw_template_selection(f: &mut Frame, app: &App, area: Rect) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Min(0),
            Constraint::Length(2),
        ])
        .margin(1)
        .split(area);

    let title = " Select Contract Template ";
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Yellow))
        .title(title);
    f.render_widget(block, area);

    if app.contract_form.templates.is_empty() {
        let mut lines = vec![
            Line::from(Span::styled(
                "No templates found",
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
            )),
            Line::raw(""),
        ];
        
        // Show error message if available
        if let Some(ref error) = app.contract_form.error {
            let error_lines: Vec<&str> = error.split('\n').collect();
            for error_line in error_lines {
                lines.push(Line::from(Span::styled(
                    error_line,
                    Style::default().fg(Color::Red),
                )));
            }
        } else {
            lines.push(Line::from(Span::styled(
                "Looking for templates in: examples/contracts/",
                Style::default().fg(Color::DarkGray),
            )));
        }
        
        lines.push(Line::raw(""));
        lines.push(Line::from(Span::styled(
            "Press 'r' to refresh",
            Style::default().fg(Color::DarkGray),
        )));
        
        let msg = Paragraph::new(lines)
            .block(Block::default().borders(Borders::NONE));
        f.render_widget(msg, chunks[0]);
        return;
    }

    let items: Vec<ListItem> = app.contract_form.templates
        .iter()
        .enumerate()
        .map(|(i, template)| {
            let is_selected = app.contract_form.selected_template_index == Some(i);
            let prefix = if is_selected { "▶ " } else { "  " };
            let name_style = if is_selected {
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };
            
            ListItem::new(vec![
                Line::from(vec![
                    Span::styled(prefix, name_style),
                    Span::styled(&template.name, name_style),
                ]),
                Line::from(vec![
                    Span::raw("    "),
                    Span::styled(
                        if template.description.len() > 60 {
                            format!("{}...", &template.description[..57])
                        } else {
                            template.description.clone()
                        },
                        Style::default().fg(Color::DarkGray),
                    ),
                ]),
            ])
        })
        .collect();

    let list = List::new(items)
        .block(Block::default().borders(Borders::NONE));
    f.render_widget(list, chunks[0]);

    let hint = Paragraph::new(Line::from(vec![
        Span::styled("↑/↓", Style::default().fg(Color::Cyan)),
        Span::styled(" Select template  ", Style::default().fg(Color::DarkGray)),
        Span::styled("Enter", Style::default().fg(Color::Green)),
        Span::styled(" Continue  ", Style::default().fg(Color::DarkGray)),
        Span::styled("Esc", Style::default().fg(Color::Red)),
        Span::styled(" Cancel", Style::default().fg(Color::DarkGray)),
    ]));
    f.render_widget(hint, chunks[1]);
}

fn draw_variable_input(f: &mut Frame, app: &App, area: Rect) {
    if app.contract_form.variables.is_empty() {
        let msg = Paragraph::new(Line::from(Span::styled(
            "No variables to fill",
            Style::default().fg(Color::Yellow),
        )))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Yellow))
                .title(" Create Contract "),
        );
        f.render_widget(msg, area);
        return;
    }

    let total_vars = app.contract_form.variables.len();
    let current_var = app.contract_form.selected_variable_index + 1;
    
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Template info
            Constraint::Length(3), // Current variable
            Constraint::Min(0),    // All variables list
            Constraint::Length(2),  // Hints
        ])
        .margin(1)
        .split(area);

    let title = format!(" Create Contract (Variable {}/{}) ", current_var, total_vars);
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Yellow))
        .title(title);
    f.render_widget(block, area);

    // Show template name
    let template_name = app.contract_form.selected_template_index
        .and_then(|i| app.contract_form.templates.get(i))
        .map(|t| t.name.clone())
        .unwrap_or_else(|| "Unknown".to_string());
    
    let template_info = Paragraph::new(vec![
        Line::from(vec![
            Span::styled("Template: ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
            Span::styled(template_name, Style::default().fg(Color::White)),
        ]),
    ])
    .block(Block::default().borders(Borders::BOTTOM));
    f.render_widget(template_info, chunks[0]);

    // Current variable input
    if let Some((var_name, var_value)) = app.contract_form.variables.get(app.contract_form.selected_variable_index) {
        let var_type = VariableType::detect(var_name);
        let cursor = "█";
        let display_value = format!("{}{}", var_value, cursor);
        
        let mut input_lines = vec![
            Line::from(vec![
                Span::styled("▶ ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
                Span::styled(format!("{}: ", var_name), Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
                Span::styled(display_value, Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
            ]),
        ];
        
        // Add format hint
        input_lines.push(Line::from(vec![
            Span::raw("  "),
            Span::styled("Format: ", Style::default().fg(Color::DarkGray)),
            Span::styled(var_type.format_hint(), Style::default().fg(Color::Cyan)),
        ]));
        
        // Add suggestion for timestamp fields
        if var_type == VariableType::Timestamp && var_value.is_empty() {
            let suggestion = app.get_timestamp_suggestion();
            input_lines.push(Line::from(vec![
                Span::raw("  "),
                Span::styled("Tip: Press 't' to use current date/time: ", Style::default().fg(Color::DarkGray)),
                Span::styled(suggestion, Style::default().fg(Color::Green)),
            ]));
            input_lines.push(Line::from(vec![
                Span::raw("  "),
                Span::styled("Examples: ", Style::default().fg(Color::DarkGray)),
                Span::styled("2024-12-20, 2024-12-20 15:30, today, tomorrow, +7 days", Style::default().fg(Color::Cyan)),
            ]));
        }
        
        // Show validation error if any
        if let Some(ref err) = app.contract_form.error {
            if err.contains(var_name) {
                input_lines.push(Line::from(vec![
                    Span::raw("  "),
                    Span::styled("✗ ", Style::default().fg(Color::Red)),
                    Span::styled(err, Style::default().fg(Color::Red)),
                ]));
            }
        }
        
        let input = Paragraph::new(input_lines)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Yellow))
                    .title(" Current Field "),
            );
        f.render_widget(input, chunks[1]);
        
        // Show account suggestions if this is an account field
        let show_account_suggestions = app.contract_form.show_account_suggestions && 
                                      !app.get_account_suggestions_for_contract().is_empty();
        if show_account_suggestions {
            let suggestions = app.get_account_suggestions_for_contract();
            let suggestion_items: Vec<Line> = suggestions
                .iter()
                .enumerate()
                .take(8) // Max 8 suggestions
                .map(|(i, acc)| {
                    let is_current = app.contract_form.account_suggestion_index == Some(i);
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
            f.render_widget(suggestion_widget, chunks[2]);
            return; // Don't show variables list when showing suggestions
        }
    }

    // All variables list
    let var_items: Vec<ListItem> = app.contract_form.variables
        .iter()
        .enumerate()
        .map(|(i, (var_name, var_value))| {
            let is_selected = i == app.contract_form.selected_variable_index;
            let prefix = if is_selected { "▶ " } else { "  " };
            let name_style = if is_selected {
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };
            
            let var_type = VariableType::detect(var_name);
            let value_display = if var_value.is_empty() {
                "(empty)".to_string()
            } else if var_value.len() > 30 {
                format!("{}...", &var_value[..27])
            } else {
                var_value.clone()
            };
            
            // Validate value to show status
            let is_valid = if var_value.trim().is_empty() {
                false
            } else {
                var_type.validate(var_value).is_ok()
            };
            
            let value_color = if var_value.is_empty() {
                Color::DarkGray
            } else if is_valid {
                Color::Green
            } else {
                Color::Red
            };
            
            ListItem::new(vec![
                Line::from(vec![
                    Span::styled(prefix, name_style),
                    Span::styled(var_name, name_style),
                    Span::raw(": "),
                    Span::styled(value_display, Style::default().fg(value_color)),
                    if !is_valid && !var_value.is_empty() {
                        Span::styled(" ⚠", Style::default().fg(Color::Red))
                    } else {
                        Span::raw("")
                    },
                ]),
            ])
        })
        .collect();

    let var_list = List::new(var_items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan))
                .title(" All Variables "),
        );
    f.render_widget(var_list, chunks[2]);

    // Hints
    if chunks.len() > 3 {
        let all_filled = app.contract_form.variables.iter().all(|(_, v)| !v.is_empty());
        let is_account_field = app.contract_form.variables
            .get(app.contract_form.selected_variable_index)
            .map(|(name, _)| crate::ui::app::App::is_account_field(name))
            .unwrap_or(false);
        
        let hint_text = if is_account_field && app.contract_form.show_account_suggestions {
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
        } else if all_filled {
            Line::from(vec![
                Span::styled("↑/↓", Style::default().fg(Color::Cyan)),
                Span::styled(" Navigate  ", Style::default().fg(Color::DarkGray)),
                Span::styled("Enter", Style::default().fg(Color::Green)),
                Span::styled(" Create Contract  ", Style::default().fg(Color::DarkGray)),
                Span::styled("Esc", Style::default().fg(Color::Red)),
                Span::styled(" Back", Style::default().fg(Color::DarkGray)),
            ])
        } else {
            Line::from(vec![
                Span::styled("↑/↓", Style::default().fg(Color::Cyan)),
                Span::styled(" Navigate  ", Style::default().fg(Color::DarkGray)),
                Span::styled("Enter", Style::default().fg(Color::Cyan)),
                Span::styled(" Next field  ", Style::default().fg(Color::DarkGray)),
                Span::styled("Esc", Style::default().fg(Color::Red)),
                Span::styled(" Back", Style::default().fg(Color::DarkGray)),
            ])
        };
        
        let hint = Paragraph::new(hint_text);
        f.render_widget(hint, chunks[3]);
    }

    // Show error or success message
    if let Some(ref err) = app.contract_form.error {
        let error_area = Rect {
            x: chunks[3].x,
            y: chunks[3].y + 2,
            width: chunks[3].width,
            height: 3,
        };
        let msg = Paragraph::new(Line::from(vec![
            Span::styled("✗ ", Style::default().fg(Color::Red)),
            Span::styled(err.as_str(), Style::default().fg(Color::Red)),
        ]))
        .wrap(Wrap { trim: true });
        f.render_widget(msg, error_area);
    } else if let Some(ref success) = app.contract_form.success {
        let success_area = Rect {
            x: chunks[3].x,
            y: chunks[3].y + 2,
            width: chunks[3].width,
            height: 3,
        };
        let msg = Paragraph::new(Line::from(vec![
            Span::styled("✓ ", Style::default().fg(Color::Green)),
            Span::styled(success.as_str(), Style::default().fg(Color::Green)),
        ]))
        .wrap(Wrap { trim: true });
        f.render_widget(msg, success_area);
    }
}

fn draw_status_bar(f: &mut Frame, app: &App, area: Rect) {
    let help_text = if app.loading {
        "Loading...".to_string()
    } else {
        match app.current_view {
            View::Participants => {
                " ↑/↓:Select  Enter:View Details  Ctrl-R:Refresh  q:Quit ".to_string()
            }
            View::ParticipantDetail => {
                " b:Back  Ctrl-R:Refresh  q:Quit ".to_string()
            }
            View::SmartContracts => {
                " Ctrl-R:Refresh  ←/→:Tabs  q:Quit ".to_string()
            }
            View::Transfer => {
                if app.transfer_form.selected_field <= 1 {
                    " Tab:Cycle Accounts  Enter:Accept  ↑/↓:Fields  ←/→:Tabs  q:Quit ".to_string()
                } else {
                    " ↑/↓:Fields  Enter:Execute  Esc:Clear  ←/→:Tabs  q:Quit ".to_string()
                }
            }
            View::History => " Ctrl-R:Refresh  q:Quit ".to_string(),
            View::Future => " Ctrl-R:Refresh  q:Quit ".to_string(),
            View::CreateContract => {
                match app.contract_form.step {
                    ContractFormStep::SelectTemplate => {
                        " ↑/↓:Select  Enter:Continue  Esc:Cancel  q:Quit ".to_string()
                    }
                    ContractFormStep::FillVariables => {
                        let is_account = app.contract_form.variables
                            .get(app.contract_form.selected_variable_index)
                            .map(|(name, _)| crate::ui::app::App::is_account_field(name))
                            .unwrap_or(false);
                        if is_account && app.contract_form.show_account_suggestions {
                            " Tab:Cycle  Enter:Accept  ↑/↓:Fields  Esc:Back  q:Quit ".to_string()
                        } else {
                            " ↑/↓:Navigate  Enter:Next/Create  t:Timestamp  Esc:Back  q:Quit ".to_string()
                        }
                    }
                }
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

    // Right: context-aware info
    let info = match app.current_view {
        View::Participants => {
            format!(" {} participants ", app.participants.len())
        }
        View::ParticipantDetail => {
            if let Some(ref detail) = app.participant_detail {
                format!(" {} accounts | {} contracts | {} total balance ", 
                    detail.accounts.len(), 
                    detail.contracts.len(),
                    grpc::format_balance(detail.total_balance))
            } else {
                " Loading... ".to_string()
            }
        }
        View::SmartContracts => {
            format!(" {} contracts ", app.smart_contracts.len())
        }
        View::Transfer => {
            // Show available accounts for transfer
            format!(" {} accounts available ", app.accounts.len())
        }
        View::History => {
            format!(" {} transactions ", app.history.len())
        }
        View::Future => {
            format!(" {} scheduled events ", app.future_events.len())
        }
        View::CreateContract => {
            match app.contract_form.step {
                ContractFormStep::SelectTemplate => {
                    format!(" {} templates ", app.contract_form.templates.len())
                }
                ContractFormStep::FillVariables => {
                    let filled = app.contract_form.variables.iter().filter(|(_, v)| !v.is_empty()).count();
                    format!(" {}/{} variables filled ", filled, app.contract_form.variables.len())
                }
            }
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
