# Scalegraph

A distributed ledger system for multi-party ecosystems, built with Elixir/OTP, Mnesia, and gRPC.

## Overview

Scalegraph provides atomic multi-party transactions and account management for ecosystem participants. It's designed for scenarios where multiple organizations need to coordinate financial flows with strong consistency guarantees.

The system follows a **separation of concerns** architecture:
- **Ledger Layer**: Immutable double-entry bookkeeping with generic transfers
- **Business/Contract Layer**: Business logic, contracts, and workflows (invoices, loans, revenue-share, etc.)

This design ensures the ledger remains simple and replayable while supporting complex business scenarios. See [`docs/LEDGER_DESIGN.md`](docs/LEDGER_DESIGN.md) for detailed architecture documentation.

## Features

- **Atomic Transactions**: Multi-party transfers with ACID guarantees via Mnesia
- **Separation of Concerns**: Clean separation between ledger (double-entry bookkeeping) and business logic layers
- **Generic Transfers**: Flexible transaction model that can represent any business scenario
- **Participant Management**: Organizations with defined roles in the ecosystem
- **Participant Services**: Declare and discover capabilities (e.g., "financing", "access_control")
- **Account Types**: Operating, receivables, payables, escrow, fees, and usage accounts
- **Three-Party Settlements**: Embedded financing and complex multi-party atomic transfers
- **gRPC API**: High-performance API for integration
- **Rust TUI CLI**: Terminal interface for interacting with the ledger
- **Replayable History**: All transactions are self-describing and can reconstruct entire state

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

Scalegraph follows a layered architecture with clear separation of concerns:

### Ledger Layer
The immutable ledger handles only double-entry bookkeeping:
- Generic transfers with entries that sum to zero
- Account balances
- Transaction audit trail
- **No business semantics** - the ledger doesn't know what transactions represent

### Business/Contract Layer
Business logic and contracts are handled separately:
- Invoices, loans, revenue-share contracts
- Conditional payments and subscriptions
- State machines and workflows
- References ledger transactions but stores metadata separately

This design provides:
- **Flexibility**: New business constructs require no changes to the ledger
- **Replayability**: All transactions are self-describing
- **Scalability**: Can build smart contracts on top of the business layer

For detailed architecture documentation, see [`docs/LEDGER_DESIGN.md`](docs/LEDGER_DESIGN.md).

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

- **[`docs/LEDGER_DESIGN.md`](docs/LEDGER_DESIGN.md)**: Architecture design, separation of concerns, and implementation plan
- **[`docs/GIT_WORKFLOW.md`](docs/GIT_WORKFLOW.md)**: Git workflow guide for contributors
- **[`ARCHITECTURE.md`](ARCHITECTURE.md)**: System architecture and design decisions
- **[`CONVENTIONS.md`](CONVENTIONS.md)**: Coding conventions and best practices
- **[`PROJECT.md`](PROJECT.md)**: Detailed component breakdown and data flow

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
