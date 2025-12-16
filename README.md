# Scalegraph

A distributed ledger system for multi-party ecosystems, built with Elixir/OTP, Mnesia, and gRPC.

## Overview

Scalegraph provides atomic multi-party transactions and account management for ecosystem participants. It's designed for scenarios where multiple organizations need to coordinate financial flows with strong consistency guarantees.

The system follows a **three-layer architecture** with strict separation of concerns:

1. **Layer 1: Pure Core Ledger** - Immutable double-entry bookkeeping with generic transfers
2. **Layer 2: Business Rules Layer** - Business logic with explicit financial terminology (invoices, loans, revenue-share, subscriptions)
3. **Layer 3: Smart Contracts Layer** - Automation, cron scheduling, and agent-driven contract management

This design ensures the ledger remains simple and replayable while supporting complex business scenarios and automated workflows. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for detailed architecture documentation.

## Features

### Core Ledger (Layer 1)
- **Atomic Transactions**: Multi-party transfers with ACID guarantees via Mnesia
- **Generic Transfers**: Flexible transaction model that can represent any business scenario
- **Account Types**: Operating, receivables, payables, escrow, fees, and usage accounts
- **Immutable Audit Trail**: All transactions are self-describing and can reconstruct entire state
- **Multi-Party Settlements**: Embedded financing and complex multi-party atomic transfers

### Business Rules (Layer 2)
- **Explicit Financial Terminology**: Loans, invoices, revenue-share, subscriptions
- **Business Contracts**: Track business semantics separately from ledger
- **Participant Management**: Organizations with defined roles in the ecosystem
- **Participant Services**: Declare and discover capabilities (e.g., "financing", "access_control")

### Smart Contracts (Layer 3)
- **Automation**: Conditional execution based on triggers (time, balance, events)
- **Cron Scheduling**: Periodic contract execution (e.g., monthly subscription billing)
- **Agent-driven Management**: Active monitoring and execution of contracts
- **Execution History**: Complete audit trail of all contract executions
- **Reusable Examples**: Marketplace membership, supplier registration, ecosystem partner membership

### Infrastructure
- **gRPC API**: High-performance API for integration
- **Rust TUI CLI**: Terminal interface for interacting with the ledger
- **Three-Layer Architecture**: Clean separation of concerns for maintainability and scalability

## Requirements

| Tool | Version | Purpose |
|------|---------|---------|
| Erlang/OTP | 25+ | Runtime for Elixir |
| Elixir | 1.14+ | Server implementation |
| Rust | 1.70+ | CLI implementation |
| protoc | 3.x | Protocol Buffers compiler |
| just | 1.x | Command runner (optional) |

## Environment Setup

### macOS (Homebrew)

```bash
# Install all dependencies at once
brew install erlang elixir rust protobuf just

# Verify installation
just check-env
```

### Ubuntu/Debian

```bash
# Erlang & Elixir
sudo apt-get update
sudo apt-get install -y erlang elixir

# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Protobuf compiler
sudo apt-get install -y protobuf-compiler

# Just (command runner)
cargo install just
```

### Using asdf (Recommended for Version Management)

```bash
# Install asdf first: https://asdf-vm.com/guide/getting-started.html

asdf plugin add erlang && asdf plugin add elixir && asdf plugin add rust
asdf install erlang latest && asdf install elixir latest && asdf install rust latest
asdf global erlang latest && asdf global elixir latest && asdf global rust latest
```

### Verify Installation

```bash
# Using just
just check-env

# Or manually
elixir --version    # Elixir 1.14+
erl -version        # Erlang/OTP 25+
rustc --version     # rustc 1.70+
protoc --version    # libprotoc 3.x
```

## Quick Start (with just)

```bash
just setup          # Install Elixir & Rust deps
just init           # Seed database
just run            # Start server (terminal 1)
just cli            # Launch TUI (terminal 2)
```

## Installation (Manual)

```bash
# Get dependencies
mix deps.get

# Compile
mix compile

# Build CLI
cd cli && cargo build --release && cd ..
```

## Running

### Start the Server

```bash
# Interactive mode
iex -S mix

# Or as a standalone application
mix run --no-halt
```

The gRPC server starts on port `50051` by default.

### Seed Data

In `iex`:

```elixir
Scalegraph.Seed.run()
```

This creates the initial ecosystem participants:
- ASSA ABLOY (access provider)
- SEB (banking partner)
- Beauty Hosting (ecosystem partner)
- Schampo etc (supplier)
- Clipper Oy (supplier)
- Hairgrowers United Inc (equipment provider)

### CLI

```bash
cd cli
cargo build --release
./target/release/scalegraph
```

## Usage Examples

### Create a Participant

```elixir
alias Scalegraph.Participant.Core, as: Participant

Participant.create_participant("my_org", "My Organization", :supplier, %{
  "country" => "SE"
})
```

### Create an Account

```elixir
Participant.create_participant_account("my_org", :operating, 0)
```

### Transfer Funds

The ledger uses **generic transfers** that can represent any business scenario:

```elixir
alias Scalegraph.Ledger.Core, as: Ledger

# Credit an account (single-entry, creates offset entry automatically)
Ledger.credit("my_org:operating", 1000, "initial_deposit")

# Atomic multi-party transfer (entries must sum to zero)
Ledger.transfer([
  {"sender:operating", -500},
  {"receiver:operating", 500}
], "payment_ref")

# Multi-party transfer with fees (entries can be unbalanced)
Ledger.transfer([
  {"payer:operating", -1000},
  {"payee:operating", 950},
  {"platform:fees", 50}
], "payment_with_fee")
```

**Key Points:**
- All transfers are **generic** - the ledger doesn't know if it's a payment, invoice, or loan
- Entries can sum to zero (balanced) or be unbalanced (allows fees, taxes, etc.)
- Business semantics are handled in the Business/Contract Layer

### Declare Participant Services

```elixir
alias Scalegraph.Participant.Core, as: Participant

# Declare services a participant provides
Participant.add_service("seb", "financing")
Participant.add_service("seb", "payment_processing")
Participant.add_service("assa_abloy", "access_control")

# List services for a participant
Participant.list_services("seb")  # {:ok, ["financing", "payment_processing"]}
```

### Three-Party Atomic Settlement

Scalegraph supports complex multi-party atomic transfers, including embedded financing:

```elixir
alias Scalegraph.Ledger.Core, as: Ledger

# Three-party settlement with embedded financing
# SEB provides financing, buyer contributes, seller receives full amount
Ledger.transfer([
  {"seb:operating", -150023},           # SEB provides $1,500.23 financing
  {"salon_glamour:operating", -49977},  # Salon contributes $499.77
  {"beauty_hosting:fees", 200000}       # Beauty Hosting receives $2,000.00
], "embedded_financing_settlement")
```

**Key Features:**
- ✅ **Atomic**: All or nothing - if any account lacks funds, entire transaction aborts
- ✅ **Multi-party**: Supports any number of parties
- ✅ **Balanced or unbalanced**: Sum doesn't need to be zero (allows fees, taxes, etc.)
- ✅ **Audit trail**: Transaction recorded with all entries

### Smart Contracts

Create automated contracts that execute based on conditions:

```elixir
alias Scalegraph.SmartContracts.Examples

# Marketplace membership contract - automatically charges all participants monthly
{:ok, contract} = Examples.create_marketplace_membership("beauty_hosting",
  monthly_fee_cents: 6000,        # 60 EUR per month
  grace_period_months: 3,         # 3 months grace period
  payment_months: 9,               # 9 monthly payments
  renewal_notice_days: 30         # 30 days notice for renewal
)

# Contract automatically executes monthly via scheduler
# - Checks daily for due payments
# - Charges all participants
# - Records execution history
```

See [`docs/SMART_CONTRACT_EXAMPLES.md`](docs/SMART_CONTRACT_EXAMPLES.md) for more smart contract examples.

## Participant Services

Participants can declare services they provide (e.g., "financing", "access_control", "payment_processing"). Services are **fully persisted** in the database and can be used for service discovery.

### Storage
- Services are stored as the **6th field** in the `scalegraph_participants` table
- Field type: **list of strings** (service identifiers)
- Persisted with `disc_copies` (persistent storage)
- Backward compatible: old records default to empty list `[]`

### Service Management

```elixir
alias Scalegraph.Participant.Core, as: Participant

# Add a service
Participant.add_service("seb", "financing")

# Remove a service
Participant.remove_service("seb", "financing")

# List all services for a participant
Participant.list_services("seb")  # {:ok, ["financing", "payment_processing"]}
```

### Service Discovery

Find participants that provide a specific service:

```elixir
# Get all participants
{:ok, participants} = Participant.list_participants()

# Filter for financing providers
financing_providers = Enum.filter(participants, fn p -> 
  "financing" in (p.services || [])
end)
```

### gRPC Endpoints

- `AddService` - Add a service to a participant
- `RemoveService` - Remove a service from a participant
- `ListServices` - List all services for a participant

## Configuration

In `config/config.exs`:

```elixir
config :scalegraph,
  grpc_port: 50051,
  # Mnesia storage type: :disc_copies (persistent) or :ram_copies (in-memory)
  mnesia_storage: :disc_copies

# Mnesia directory for disc_copies
config :mnesia, dir: ~c"./priv/mnesia_data"
```

## Testing

```bash
mix test
```

## Architecture

Scalegraph follows a **three-layer architecture** with strict separation of concerns:

### Layer 1: Pure Core Ledger
The immutable ledger handles only double-entry bookkeeping:
- Generic transfers with entries that sum to zero
- Account balances
- Transaction audit trail
- **No business semantics** - the ledger doesn't know what transactions represent

### Layer 2: Business Rules Layer
Business logic with explicit financial terminology:
- Invoices, loans, revenue-share contracts
- Subscriptions and conditional payments
- References ledger transactions but stores metadata separately
- Uses explicit financial terminology (loans, invoices, etc.)

### Layer 3: Smart Contracts Layer
Automation and agent-driven contract management:
- Cron-based scheduling (e.g., monthly subscription billing)
- Conditional execution based on triggers
- Active monitoring and execution of contracts
- Reusable contract examples (marketplace membership, supplier registration, etc.)

This design provides:
- **Flexibility**: New business constructs require no changes to the ledger
- **Replayability**: All transactions are self-describing
- **Automation**: Smart contracts handle recurring payments and workflows
- **Scalability**: Each layer can be scaled independently

For detailed architecture documentation, see [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Project Structure

```
scalegraph-elexir/
├── proto/                   # Protobuf definitions (single source of truth)
│   └── ledger.proto         # gRPC service definitions
├── lib/
│   └── scalegraph/
│       ├── ledger/          # Ledger layer (double-entry bookkeeping)
│       ├── business/        # Business/Contract layer
│       ├── participant/     # Organization management
│       ├── storage/         # Mnesia schema and setup
│       └── proto/           # Generated protobuf modules
├── cli/                     # Rust TUI client
├── mcp/                     # Model Context Protocol server
├── config/                  # Configuration files
├── docs/                    # Documentation
│   ├── LEDGER_DESIGN.md     # Architecture and design decisions
│   ├── GIT_WORKFLOW.md      # Git workflow guide
│   └── ...                  # Other documentation
├── priv/                    # Static assets
└── test/                    # Test files
```

## Documentation

- **[`ARCHITECTURE.md`](ARCHITECTURE.md)**: Three-layer architecture, design decisions, and examples
- **[`PROJECT.md`](PROJECT.md)**: Detailed component breakdown and data flow
- **[`CONVENTIONS.md`](CONVENTIONS.md)**: Coding conventions and best practices
- **[`docs/SMART_CONTRACT_EXAMPLES.md`](docs/SMART_CONTRACT_EXAMPLES.md)**: Smart contract examples and usage
- **[`docs/GIT_WORKFLOW.md`](docs/GIT_WORKFLOW.md)**: Git workflow guide for contributors
- **[`docs/CLI-USER-GUIDE.md`](docs/CLI-USER-GUIDE.md)**: CLI user guide
- **[`docs/MCP.md`](docs/MCP.md)**: Model Context Protocol server documentation

## Contributing

### Git Workflow

For larger changes, use feature branches:

```bash
# Create feature branch
git checkout -b feature/your-feature-name

# Work and commit regularly
git add .
git commit -m "feat: description of changes"

# When ready, merge to main
git checkout main
git merge feature/your-feature-name
```

**Before merging:**
- Run all tests: `just test`
- Check formatting: `just fmt`
- Run linter: `just lint`
- Verify everything works

See [`docs/GIT_WORKFLOW.md`](docs/GIT_WORKFLOW.md) for detailed workflow guidelines.

### Code Quality

- Follow conventions in [`CONVENTIONS.md`](CONVENTIONS.md)
- All code must be formatted: `mix format`
- No Credo warnings: `mix credo --strict`
- All tests must pass: `mix test`

## License

Proprietary
