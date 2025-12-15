# LLM Context Guide for Scalegraph

This document provides essential context for LLMs working with the Scalegraph codebase. Read this first to understand the project structure, conventions, and patterns.

---

## Project Overview

**Scalegraph** is a distributed ledger system for multi-party ecosystems, built with:
- **Elixir/OTP** - Server implementation with fault-tolerant architecture
- **Mnesia** - Distributed, in-memory database with ACID transactions
- **gRPC** - High-performance API for service-to-service communication
- **Rust** - TUI CLI client

**Purpose**: Enable atomic financial transactions between multiple organizations in a business network with strong consistency guarantees.

---

## Essential Documentation Files

When working on this project, **always reference these files first**:

1. **`CONVENTIONS.md`** - Complete coding conventions and best practices
   - Elixir style guide
   - Error handling patterns
   - Mnesia patterns
   - gRPC patterns
   - Domain conventions
   - Testing strategies

2. **`ARCHITECTURE.md`** - System architecture and design decisions
   - Layer responsibilities
   - Transaction model
   - Database schema
   - Error handling strategy
   - Concurrency model

3. **`PROJECT.md`** - Detailed component breakdown and data flow
   - Component descriptions
   - Domain model
   - Data flow diagrams

4. **`README.md`** - Quick start and usage examples

---

## Project Structure

```
scalegraph-elexir/
├── lib/scalegraph/          # Elixir application code
│   ├── application.ex       # OTP Application entry point
│   ├── ledger/              # Ledger domain
│   │   ├── core.ex          # Business logic (account operations, transfers)
│   │   └── server.ex        # gRPC server implementation
│   ├── participant/         # Participant domain
│   │   ├── core.ex          # Business logic (participant CRUD)
│   │   └── server.ex        # gRPC server implementation
│   ├── storage/
│   │   └── schema.ex        # Mnesia schema and table definitions
│   ├── proto/               # Generated protobuf modules
│   ├── business/            # Business transaction logic
│   └── seed.ex              # Demo data seeding
├── cli/                      # Rust TUI client
│   ├── src/
│   │   ├── main.rs          # Entry point
│   │   ├── grpc/            # gRPC client
│   │   └── ui/               # TUI components
│   └── proto/               # Protobuf definitions
├── test/                     # Test files
├── config/                   # Configuration files
├── priv/
│   ├── protos/              # Protobuf source files
│   └── mnesia_data/         # Mnesia database files
└── Justfile                  # Command runner recipes
```

---

## Architecture Layers

The codebase follows a **layered architecture**:

```
┌─────────────────────────────────┐
│  Transport Layer (gRPC)         │  ← Scalegraph.Endpoint
├─────────────────────────────────┤
│  Service Layer                   │  ← Ledger.Server, Participant.Server
│  (Request validation,            │     (Error mapping, proto conversion)
│   error mapping)                 │
├─────────────────────────────────┤
│  Core Layer                      │  ← Ledger.Core, Participant.Core
│  (Business logic,                │     (Domain operations, transactions)
│   transaction management)        │
├─────────────────────────────────┤
│  Storage Layer (Mnesia)          │  ← Storage.Schema
│  (Data persistence,              │     (Table definitions, transactions)
│   ACID transactions)             │
└─────────────────────────────────┘
```

**Key Principle**: Each layer has clear responsibilities. Business logic lives in Core, not in Servers.

---

## Key Conventions (Summary)

### Error Handling

- **Core modules**: Return `{:ok, result}` or `{:error, reason}` tuples
- **No exceptions** in domain logic - use structured error tuples
- **Structured errors**: Use matchable tuples, not string messages
  - `:not_found`
  - `:account_exists`
  - `{:insufficient_funds, account_id, balance, amount}`
  - `{:invalid_role, role, valid_roles}`
- **gRPC servers**: Convert domain errors to `GRPC.RPCError` at boundaries

### Mnesia Patterns

- **Always wrap in transactions**:
  ```elixir
  result = :mnesia.transaction(fn ->
    # operations
  end)
  ```
- **Use `:mnesia.abort/1`** for rollbacks with errors
- **Access tables via Schema module**: `Schema.accounts_table()`, never hardcode
- **Records are tuples**: `{table_name, key, field1, field2, ...}`

### Module Structure

1. `@moduledoc` - Brief description
2. `use/import/alias/require` statements
3. Module attributes (`@constants`)
4. Public functions with `@doc`
5. Private functions (prefixed with `defp`)

### Naming

- Modules: `PascalCase` (e.g., `Scalegraph.Ledger.Core`)
- Functions: `snake_case` (e.g., `create_account`)
- Variables: `snake_case` (e.g., `account_id`)
- Atoms: `snake_case` (e.g., `:account_exists`)

---

## Domain Model

### Participants

Organizations in the ecosystem with roles:
- `:access_provider` - Physical access control (e.g., ASSA ABLOY)
- `:banking_partner` - Financial services (e.g., SEB)
- `:ecosystem_partner` - Platform operators (e.g., Beauty Hosting)
- `:supplier` - Product suppliers
- `:equipment_provider` - Pay-per-use equipment

### Accounts

Linked to participants with types:
- `:standalone` - Independent account
- `:operating` - Main business account
- `:receivables` - Incoming payments
- `:payables` - Outgoing payments
- `:escrow` - Held funds
- `:fees` - Fee collection
- `:usage` - Pay-per-use tracking

**Account ID format**: `"{participant_id}:{account_type}"` (e.g., `"seb:operating"`)

### Transactions

- **Single-entry**: Credit or debit operations
- **Multi-entry**: Atomic transfers between multiple accounts
- All balance changes are recorded as transactions
- Transaction IDs: Random hex strings (16 bytes)

### Amounts

- Always **integers** (smallest currency unit)
- Positive = credit, Negative = debit
- No floating point

---

## Database Schema

### Tables

| Table | Key | Indices | Purpose |
|-------|-----|---------|---------|
| `scalegraph_participants` | id | - | Participant records |
| `scalegraph_accounts` | id | participant_id | Account records |
| `scalegraph_transactions` | id | - | Transaction audit log |

### Record Formats

**Participants**: `{table, id, name, role, created_at, metadata}`

**Accounts**: `{table, id, participant_id, account_type, balance, created_at, metadata}`

**Transactions**: `{table, id, type, entries, timestamp, reference}`

---

## Common Patterns

### Creating a New Feature

1. **Define domain logic in Core module** (e.g., `Ledger.Core` or `Participant.Core`)
   - Use Mnesia transactions
   - Return `{:ok, result}` or `{:error, reason}`
   - Use structured, matchable error tuples

2. **Add gRPC endpoint in Server module** (e.g., `Ledger.Server`)
   - Extract/validate request
   - Call Core function
   - Map errors to gRPC status codes
   - Convert internal types to proto types

3. **Add tests** in `test/scalegraph/`
   - Use `ExUnit.Case`
   - Clear Mnesia tables in `setup`
   - Test both success and error cases

### Error Handling Example

```elixir
# In Core module
def transfer(entries, reference) do
  result = :mnesia.transaction(fn ->
    # Validate and update accounts
    # If error:
    :mnesia.abort({:insufficient_funds, account_id, balance, amount})
  end)
  
  case result do
    {:atomic, {:ok, tx}} -> {:ok, tx}
    {:aborted, {:insufficient_funds, account_id, balance, amount}} ->
      {:error, {:insufficient_funds, account_id, balance, amount}}
  end
end

# In Server module
def transfer(request, _stream) do
  case Core.transfer(entries, reference) do
    {:ok, tx} -> transaction_to_proto(tx)
    {:error, {:insufficient_funds, account_id, balance, amount}} ->
      business_error(:failed_precondition, 
        "Account #{account_id} has balance #{balance}, cannot apply #{amount}")
  end
end
```

### Mnesia Transaction Pattern

```elixir
result = :mnesia.transaction(fn ->
  case :mnesia.read(Schema.accounts_table(), account_id) do
    [] -> :mnesia.abort({:error, :not_found})
    [record] -> 
      # Update record
      :mnesia.write(updated_record)
      {:ok, result}
  end
end)

case result do
  {:atomic, {:ok, result}} -> {:ok, result}
  {:aborted, {:error, reason}} -> {:error, reason}
  {:aborted, reason} -> {:error, reason}
end
```

---

## Important Files to Understand

### Core Business Logic

- **`lib/scalegraph/ledger/core.ex`** - Account operations, transfers, balance management
- **`lib/scalegraph/participant/core.ex`** - Participant CRUD, account creation

### gRPC Servers

- **`lib/scalegraph/ledger/server.ex`** - Ledger gRPC endpoints
- **`lib/scalegraph/participant/server.ex`** - Participant gRPC endpoints
- **`lib/scalegraph/application.ex`** - Endpoint configuration, supervision tree

### Storage

- **`lib/scalegraph/storage/schema.ex`** - Mnesia schema, table definitions, initialization

### Configuration

- **`config/config.exs`** - Application configuration
- **`mix.exs`** - Project metadata, dependencies

### Protobuf

- **`priv/protos/ledger.proto`** - Service and message definitions
- **`lib/scalegraph/proto/ledger.pb.ex`** - Generated Elixir protobuf code

---

## Testing

### Test Structure

```elixir
defmodule Scalegraph.Ledger.CoreTest do
  use ExUnit.Case, async: false  # Mnesia requires non-async

  alias Scalegraph.Ledger.Core
  alias Scalegraph.Storage.Schema

  setup do
    Schema.init()
    Schema.clear_all()
    :ok
  end

  describe "function_name/arity" do
    test "describes expected behavior" do
      # test code
    end
  end
end
```

### Key Testing Points

- Clear Mnesia tables in `setup` using `Schema.clear_all/0`
- Test both success and error paths
- Verify transaction atomicity
- Use pattern matching for error assertions: `{:error, {:insufficient_funds, _}}`

---

## Development Workflow

### Setup

```bash
just setup          # Install dependencies
just init           # Seed database
```

### Development

```bash
just run            # Start server
just test           # Run tests
just fmt            # Format code
just lint           # Lint with credo
```

### Building

```bash
just build          # Build Elixir + Rust CLI
just build-cli-release  # Build optimized CLI
```

---

## Version Requirements

- **Elixir**: 1.17+
- **OTP**: 27+
- **Rust**: 1.70+
- **protoc**: 3.x

---

## Key Dependencies

### Elixir

- `grpc` - gRPC server framework
- `protobuf` - Protocol buffer support
- `credo` - Code quality tool (dev/test only)
- `yaml_elixir` - YAML parsing for seed data

### Rust CLI

- `tonic` - gRPC client
- `ratatui` - TUI framework
- `tokio` - Async runtime

---

## When Adding New Features

1. **Read `CONVENTIONS.md`** first - understand error handling, patterns, naming
2. **Check existing Core modules** - follow the same patterns
3. **Use Mnesia transactions** - wrap all DB operations
4. **Return structured errors** - use matchable tuples, not strings
5. **Add tests** - test success and error cases
6. **Update documentation** - if adding new domain concepts

---

## Common Mistakes to Avoid

❌ **Don't**: Use `raise` or exceptions in Core modules  
✅ **Do**: Return `{:error, reason}` tuples

❌ **Don't**: Hardcode table names  
✅ **Do**: Use `Schema.accounts_table()`

❌ **Don't**: Put business logic in Server modules  
✅ **Do**: Keep business logic in Core modules

❌ **Don't**: Use string error messages in Core  
✅ **Do**: Use structured, matchable error tuples

❌ **Don't**: Skip Mnesia transactions  
✅ **Do**: Always wrap DB operations in transactions

❌ **Don't**: Return raw values from fallible operations  
✅ **Do**: Return `{:ok, result}` or `{:error, reason}`

---

## Quick Reference

### Error Reasons

- `:not_found` - Resource doesn't exist
- `:account_exists` - Account already exists
- `:participant_exists` - Participant already exists
- `{:insufficient_funds, account_id, balance, amount}` - Transfer error
- `{:insufficient_funds, balance, amount}` - Single-entry error
- `{:invalid_role, role, valid_roles}` - Invalid participant role

### gRPC Error Mapping

- `:not_found` → `NOT_FOUND`
- `:account_exists` → `ALREADY_EXISTS`
- `{:insufficient_funds, _}` → `FAILED_PRECONDITION`
- Other → `INTERNAL`

### Table Access

- `Schema.participants_table()` - Participants table
- `Schema.accounts_table()` - Accounts table
- `Schema.transactions_table()` - Transactions table
- `Schema.participant_roles()` - Valid participant roles

---

## Getting Help

When stuck or unsure:

1. **Check `CONVENTIONS.md`** - Most patterns are documented there
2. **Look at existing code** - `Ledger.Core` and `Participant.Core` are good examples
3. **Review `ARCHITECTURE.md`** - Understand the layer responsibilities
4. **Examine tests** - See how features are tested

---

## Summary

Scalegraph is a **production-grade, fault-tolerant ledger system** built with Elixir/OTP. Key principles:

- **Layered architecture** - Clear separation of concerns
- **Structured errors** - Matchable tuples, not exceptions
- **ACID transactions** - Mnesia for consistency
- **Type safety** - gRPC for strong typing
- **Testability** - Clear interfaces, dependency injection

Follow the conventions, understand the layers, and maintain consistency with existing code patterns.

