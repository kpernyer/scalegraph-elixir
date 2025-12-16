# Scalegraph CLI User Guide

A terminal-based user interface for interacting with the Scalegraph Ledger system. Built with Rust using Ratatui and Crossterm for a responsive, keyboard-driven experience.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Interface Overview](#interface-overview)
- [Views](#views)
  - [Participants View](#participants-view)
  - [Accounts View](#accounts-view)
  - [Transfer View](#transfer-view)
  - [History View](#history-view)
- [Keyboard Reference](#keyboard-reference)
- [Common Workflows](#common-workflows)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

- **Rust** (1.70 or later) - [Install Rust](https://rustup.rs/)
- **Elixir** (1.14 or later) - For running the Scalegraph server
- **protoc** - Protocol Buffers compiler (for building the gRPC client)

### Installing protoc

```bash
# macOS
brew install protobuf

# Ubuntu/Debian
apt-get install protobuf-compiler

# Arch Linux
pacman -S protobuf
```

---

## Installation

### Building from Source

```bash
# Navigate to the CLI directory
cd cli

# Build in release mode (recommended)
cargo build --release

# The binary will be at ./target/release/scalegraph
```

### Adding to PATH (Optional)

```bash
# Copy to a directory in your PATH
cp target/release/scalegraph /usr/local/bin/

# Or add the target directory to PATH
export PATH="$PATH:$(pwd)/target/release"
```

---

## Quick Start

### 1. Start the Scalegraph Server

First, ensure the Elixir server is running:

```bash
# From the project root
cd /path/to/scalegraph-elexir

# Install dependencies (first time only)
mix deps.get

# Seed the example participants (first time only)
mix run -e "Scalegraph.Seed.run()"

# Start the server
mix run --no-halt
```

The server will start on port 50051 by default.

### 2. Launch the CLI

```bash
# Connect to default server (localhost:50051)
scalegraph

# Or specify a custom server address
scalegraph --server http://192.168.1.100:50051
```

### 3. Navigate the Interface

- Press `Tab` to switch between views
- Use arrow keys or `j`/`k` to navigate lists
- Press `q` to quit

---

## Interface Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Scalegraph Ledger                                              │
│  [Participants]  [Accounts]  [Transfer]  [History]              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                                                                 │
│                        Main Content Area                        │
│                                                                 │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  q:Quit  Tab:Switch View  r:Refresh  ↑↓:Navigate  Enter:Select │
└─────────────────────────────────────────────────────────────────┘
```

The interface is divided into three sections:

1. **Tab Bar** - Shows available views, current view highlighted in yellow
2. **Main Content** - Displays the current view's content
3. **Status Bar** - Shows keyboard shortcuts and loading status

---

## Views

### Participants View

Displays all participants registered in the Scalegraph ecosystem.

```
┌─ Participants (↑↓ navigate, Enter to view accounts) ────────────┐
│ ▶ ASSA ABLOY          [Access Provider]    (assa_abloy)         │
│   SEB                  [Banking Partner]    (seb)                │
│   Beauty Hosting       [Ecosystem Partner]  (beauty_hosting)     │
│   Schampo etc          [Supplier]           (schampo_etc)        │
│   Clipper Oy           [Supplier]           (clipper_oy)         │
│   Hairgrowers United   [Equipment Provider] (hairgrowers_united) │
└─────────────────────────────────────────────────────────────────┘
```

**Actions:**
| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate participant list |
| `Enter` | View selected participant's accounts |
| `r` | Refresh participant list |

**Participant Roles:**
- **Access Provider** - Access control services (e.g., ASSA ABLOY)
- **Banking Partner** - Payment/banking services (e.g., SEB)
- **Ecosystem Partner** - Platform operators (e.g., Beauty Hosting)
- **Supplier** - Product/equipment suppliers
- **Equipment Provider** - Pay-per-use equipment providers

---

### Accounts View

Displays accounts with their types and balances.

```
┌─ Accounts for beauty_hosting (press 'a' for all) ───────────────┐
│ Account ID                      Type          Balance           │
│ ─────────────────────────────────────────────────────────────── │
│ beauty_hosting:operating        Operating         0.00          │
│ beauty_hosting:receivables      Receivables       0.00          │
│ beauty_hosting:payables         Payables          0.00          │
│ beauty_hosting:fees             Fees              0.00          │
└─────────────────────────────────────────────────────────────────┘
```

**Actions:**
| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate account list |
| `a` | Show all accounts (clear participant filter) |
| `r` | Refresh account data |

**Account Types:**
| Type | Purpose |
|------|---------|
| Operating | Main operating account |
| Receivables | Incoming payments |
| Payables | Outgoing payments |
| Escrow | Held/reserved funds |
| Fees | Fee collection |
| Usage | Pay-per-use tracking |

**Balance Colors:**
- 🟢 **Green** - Positive balance
- ⚪ **White** - Zero balance
- 🔴 **Red** - Negative balance

---

### Transfer View

Execute atomic transfers between accounts.

```
┌─ Transfer (Tab to switch fields, Enter to submit) ──────────────┐
│                                                                 │
│ From Account: beauty_hosting:payables▌                          │
│ To Account: schampo_etc:receivables                             │
│ Amount: 50000                                                   │
│ Reference: order_12345                                          │
│                                                                 │
│ Press Enter to execute transfer, Esc to clear                   │
│                                                                 │
│ Success! TX: a1b2c3d4e5f6...                                    │
└─────────────────────────────────────────────────────────────────┘
```

**Actions:**
| Key | Action |
|-----|--------|
| `↑` / `↓` | Move between form fields |
| `Enter` | Execute the transfer |
| `Esc` | Clear form and messages |
| Any character | Type into selected field |
| `Backspace` | Delete character |

**Form Fields:**
1. **From Account** - Source account ID (will be debited)
2. **To Account** - Destination account ID (will be credited)
3. **Amount** - Transfer amount in smallest unit (e.g., cents)
4. **Reference** - Optional reference string for the transaction

**Account ID Format:**
```
{participant_id}:{account_type}

Examples:
  beauty_hosting:operating
  seb:escrow
  schampo_etc:receivables
```

---

### History View

Shows transaction history for the current session.

```
┌─ Transaction History (most recent first) ───────────────────────┐
│ Transfer 500.00 from beauty_hosting:payables to                 │
│   schampo_etc:receivables (ref: order_12345, tx: a1b2c3...)     │
│ Transfer 100.00 from beauty_hosting:operating to                │
│   seb:fees (ref: platform_fee, tx: d4e5f6...)                   │
└─────────────────────────────────────────────────────────────────┘
```

The history displays all transfers executed during the current CLI session, with the most recent at the top.

---

## Keyboard Reference

### Global Keys

| Key | Action |
|-----|--------|
| `q` | Quit the application |
| `Tab` | Next view |
| `Shift+Tab` | Previous view |
| `r` | Refresh current data |

### Navigation Keys

| Key | Action |
|-----|--------|
| `↑` or `k` | Move selection up |
| `↓` or `j` | Move selection down |
| `Enter` | Select/confirm |
| `Esc` | Cancel/clear |

### Transfer View Keys

| Key | Action |
|-----|--------|
| `↑` / `↓` | Switch between fields |
| `Enter` | Execute transfer |
| `Esc` | Clear form |
| `Backspace` | Delete character |
| Any printable | Type character |

---

## Common Workflows

### Viewing a Participant's Accounts

1. Launch the CLI: `scalegraph`
2. You're in the **Participants** view by default
3. Use `↑`/`↓` to highlight the desired participant
4. Press `Enter` to view their accounts
5. The view switches to **Accounts** filtered to that participant
6. Press `a` to see all accounts again

### Making a Transfer

1. Press `Tab` until you reach the **Transfer** view
2. Type the source account in "From Account" (e.g., `beauty_hosting:payables`)
3. Press `↓` to move to "To Account"
4. Type the destination account (e.g., `schampo_etc:receivables`)
5. Press `↓` to move to "Amount"
6. Type the amount in cents (e.g., `50000` for 500.00)
7. Press `↓` to move to "Reference"
8. Type an optional reference (e.g., `order_12345`)
9. Press `Enter` to execute
10. Check for success/error message below the form

### Multi-Party Transactions

For complex transactions involving more than two accounts (e.g., payments with fees), you'll need to make multiple transfers or use the gRPC API directly. The CLI currently supports two-party transfers.

Example workflow for a payment with fee:
```
# Transfer 1: Customer pays merchant
From: customer:operating
To: merchant:receivables
Amount: 10000

# Transfer 2: Deduct platform fee from merchant
From: merchant:receivables
To: platform:fees
Amount: 250
```

---

## Troubleshooting

### Connection Failed

```
Failed to connect to server: ...
Make sure the Scalegraph Elixir server is running.
```

**Solutions:**
1. Verify the Elixir server is running: `mix run --no-halt`
2. Check the server address: `scalegraph --server http://host:port`
3. Ensure no firewall is blocking port 50051
4. Check if another process is using the port

### Empty Participant/Account Lists

**Solutions:**
1. Seed the database: `mix run -e "Scalegraph.Seed.run()"`
2. Press `r` to refresh the data
3. Check server logs for errors

### Transfer Failed: Account Not Found

```
Failed: Account {account_id} not found
```

**Solutions:**
1. Verify account ID format: `{participant}:{type}`
2. Check available accounts in the Accounts view
3. Ensure the participant has the required account type

### Transfer Failed: Insufficient Funds

```
Failed: Insufficient funds
```

**Solutions:**
1. Credit the source account first
2. Check current balance in Accounts view
3. Reduce the transfer amount

### Terminal Display Issues

If the UI appears garbled or doesn't respond:

1. Resize your terminal window
2. Ensure terminal supports UTF-8
3. Try a different terminal emulator
4. Check that your terminal supports 256 colors

### Build Errors

```
error: failed to run custom build command for `prost-build`
```

**Solutions:**
1. Install protoc: `brew install protobuf` (macOS)
2. Ensure protoc is in your PATH: `which protoc`
3. Update Rust: `rustup update`

---

## Configuration

### Command Line Options

```
scalegraph [OPTIONS]

Options:
  -s, --server <SERVER>  gRPC server address [default: http://localhost:50051]
  -h, --help             Print help
  -V, --version          Print version
```

### Environment Variables

Currently, the CLI does not use environment variables. All configuration is done via command-line arguments.

---

## Tips & Best Practices

1. **Use tab completion for account IDs** - Copy account IDs from the Accounts view to avoid typos

2. **Check balances before transfers** - Navigate to Accounts view to verify sufficient funds

3. **Use meaningful references** - References help track transactions in history

4. **Refresh regularly** - Press `r` to get the latest data from the server

5. **Use the filter feature** - Select a participant to filter accounts, making it easier to find specific accounts

---

## Support

For issues, feature requests, or contributions:

- GitHub Issues: [Report an issue](https://github.com/your-repo/scalegraph-elixir/issues)
- Documentation: See the main project README

---

*Built with Ratatui + Crossterm for Scalegraph Ledger*
