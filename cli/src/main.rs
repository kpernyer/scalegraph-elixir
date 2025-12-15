mod grpc;
mod ui;

use anyhow::Result;
use clap::Parser;
use crossterm::{
    event::{DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use grpc::ScalegraphClient;
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io;
use std::panic;
use std::time::Duration;
use tokio::time::timeout;
use ui::{App, run_app};

#[derive(Parser, Debug)]
#[command(name = "scalegraph")]
#[command(about = "TUI CLI for Scalegraph Ledger", long_about = None)]
struct Args {
    /// gRPC server address
    #[arg(short, long, default_value = "http://localhost:50051")]
    server: String,

    /// Check connection and list participants without starting TUI
    #[arg(long)]
    check: bool,
}

fn cleanup_terminal() {
    let _ = disable_raw_mode();
    let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture);
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Set up panic hook to restore terminal
    let original_hook = panic::take_hook();
    panic::set_hook(Box::new(move |panic_info| {
        cleanup_terminal();
        original_hook(panic_info);
    }));

    // Connect to gRPC server with timeout
    println!("Connecting to {}...", args.server);
    let connect_future = ScalegraphClient::connect(&args.server);
    let mut client = match timeout(Duration::from_secs(5), connect_future).await {
        Ok(Ok(c)) => {
            println!("Connected!");
            c
        }
        Ok(Err(e)) => {
            eprintln!("Failed to connect to server: {}", e);
            eprintln!("Make sure the Scalegraph Elixir server is running.");
            eprintln!("Start it with: mix run --no-halt");
            std::process::exit(1);
        }
        Err(_) => {
            eprintln!("Connection timed out after 5 seconds.");
            eprintln!("Make sure the Scalegraph Elixir server is running on {}", args.server);
            std::process::exit(1);
        }
    };

    // Check mode - test connection and exit
    if args.check {
        println!("Testing gRPC calls...");
        match timeout(Duration::from_secs(5), client.list_participants(None)).await {
            Ok(Ok(participants)) => {
                println!("✅ Server is healthy!");
                println!("Found {} participants:", participants.len());
                for p in participants {
                    println!("  - {} ({})", p.name, p.id);
                }
            }
            Ok(Err(e)) => {
                eprintln!("❌ gRPC call failed: {}", e);
                std::process::exit(1);
            }
            Err(_) => {
                eprintln!("❌ gRPC call timed out after 5 seconds");
                std::process::exit(1);
            }
        }
        return Ok(());
    }

    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app and run
    let app = App::new(client);
    let res = run_app(&mut terminal, app).await;

    // Restore terminal
    cleanup_terminal();
    terminal.show_cursor()?;

    if let Err(err) = res {
        eprintln!("Error: {:?}", err);
    }

    Ok(())
}
