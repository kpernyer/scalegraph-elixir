# Scalegraph

A distributed ledger system for multi-party ecosystems, built with Elixir/OTP, Mnesia, and gRPC.

## Overview

Scalegraph provides atomic multi-party transactions and account management for ecosystem participants. It's designed for scenarios where multiple organizations need to coordinate financial flows with strong consistency guarantees.

## Features

- **Atomic Transactions**: Multi-party transfers with ACID guarantees via Mnesia
- **Participant Management**: Organizations with defined roles in the ecosystem
- **Account Types**: Operating, receivables, payables, escrow, fees, and usage accounts
- **gRPC API**: High-performance API for integration
- **Rust TUI CLI**: Terminal interface for interacting with the ledger

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

```elixir
alias Scalegraph.Ledger.Core, as: Ledger

# Credit an account
Ledger.credit("my_org:operating", 1000, "initial_deposit")

# Atomic multi-party transfer
Ledger.transfer([
  {"sender:operating", -500},
  {"receiver:operating", 500}
], "payment_ref")
```

## Configuration

In `config/config.exs`:

```elixir
config :scalegraph,
  grpc_port: 50051
```

## Testing

```bash
mix test
```

## Project Structure

```
scalegraph-elexir/
├── lib/
│   └── scalegraph/
│       ├── ledger/          # Account and transaction logic
│       ├── participant/     # Organization management
│       ├── storage/         # Mnesia schema and setup
│       └── proto/           # Generated protobuf modules
├── cli/                     # Rust TUI client
├── config/                  # Configuration files
├── priv/                    # Static assets
└── test/                    # Test files
```

## License

Proprietary
