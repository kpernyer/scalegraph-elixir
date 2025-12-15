# Elixir Coding Conventions & Best Practices

This document defines **opinionated, production-grade Elixir engineering standards** for the Scalegraph codebase. These conventions ensure consistency, maintainability, and reliability across all Elixir code.

---

## 1. Elixir Version, Toolchain & Baseline

- **Minimum Elixir version**: Always assume **Elixir 1.17+** and **OTP 27+** as baseline.
- Do **not downgrade** toolchain because of external dependencies that lag; instead:
  - Prefer actively maintained hex packages.
  - Fork or replace stale dependencies.
- **Version policy**:
  - All new projects must target latest stable Elixir/OTP.
  - Track version requirements in `mix.exs`:
  ```elixir
  def project do
    [
      elixir: "~> 1.17",
      otp_release: "~> 27"
    ]
  end
  ```

---

## 2. Architectural Opinions

### 2.1 gRPC with Tonic (Elixir)

- For internal service-to-service communication.
- Strong typing, streaming, codegen, performance.
- **Opinion**: **gRPC is mandatory for intra-service communication.**
- Use `tonic` (Elixir gRPC library) for server implementations.

### 2.2 OTP & Supervision

- OTP is the foundation of fault-tolerant systems.
- Supervisor trees for process lifecycle management.
- GenServer for stateful processes.
- **Opinion**: **All long-running processes must be supervised.**
  No orphaned processes. Use OTP patterns, not raw `spawn`.

---

## 3. Elixir Code Style

### 3.1 Module Structure

Modules follow a consistent structure:

```elixir
defmodule Scalegraph.Module.Name do
  @moduledoc """
  Brief description of the module's purpose.
  """

  # 1. use/import/alias/require
  use SomeModule
  alias Scalegraph.Other.Module

  # 2. Module attributes
  @some_constant :value

  # 3. Public functions with @doc
  @doc """
  Description of what the function does.
  """
  def public_function(arg) do
    # implementation
  end

  # 4. Private functions (prefixed with defp)
  defp private_helper(arg) do
    # implementation
  end
end
```

**Required structure**:
1. `@moduledoc` with brief description
2. `use/import/alias/require` statements
3. Module attributes (`@constants`)
4. Public functions with `@doc`
5. Private functions (prefixed with `defp`)

### 3.2 Naming Conventions

- **Modules**: `PascalCase` (e.g., `Scalegraph.Ledger.Core`)
- **Functions**: `snake_case` (e.g., `create_account`)
- **Variables**: `snake_case` (e.g., `account_id`)
- **Module Attributes**: `@snake_case` (e.g., `@accounts_table`)
- **Atoms**: `snake_case` (e.g., `:account_exists`)

### 3.3 Function Arguments

- Use guard clauses for type validation:
  ```elixir
  def create_account(id, balance) when is_binary(id) and is_integer(balance) do
  ```

- Default arguments use `\\`:
  ```elixir
  def create_account(id, balance \\ 0, metadata \\ %{})
  ```

### 3.4 Pattern Matching

- Prefer pattern matching in function heads over conditionals
- Use `case` for matching on single values
- Prefer `with` over nested `case` statements
- Use `with` for chaining operations that may fail:
  ```elixir
  with {:ok, participant} <- get_participant(id),
       {:ok, accounts} <- get_accounts(id) do
    {:ok, %{participant: participant, accounts: accounts}}
  end
  ```

### 3.5 Immutability

- Immutable by default: all data structures are immutable
- Prefer iterator transforms over mutating loops
- Use `Enum.map`, `Enum.filter`, `Enum.each` for transformations

### 3.6 Data Modeling

- Use structs for domain entities instead of raw maps
- Prefer atoms over strings for known values (e.g., `:operating` vs `"operating"`)
- Keep structs focused; avoid "god structs" with many `nil` fields unless modeling sparse data
- Use newtypes for IDs instead of raw `String` (e.g., `%Account{id: account_id}` where `account_id` is validated)
- Prefer enums over boolean flags or magic strings

---

## 4. Error Handling

### 4.1 Core Principles

- **No exceptions in domain logic**: Core modules, services, and repositories must return tagged tuples
- Use structured error tuples, not exceptions for control flow:
  - Success: `{:ok, result}`
  - Error: `{:error, reason}` or `{:error, {type, message}}`
  - Never return raw values for operations that can fail

- **Errors must be structured and matchable**: Avoid `String`ly‑typed errors. Use structured tuples that can be pattern matched.

### 4.2 Common Error Reasons

- `:not_found` - Resource doesn't exist
- `:account_exists` - Account already exists
- `:participant_exists` - Participant already exists
- `{:insufficient_funds, account_id, balance, amount}` - Balance too low (structured tuple)
- `{:insufficient_funds, balance, amount}` - Balance too low for single-entry operations
- `{:invalid_role, role, valid_roles}` - Invalid participant role

### 4.3 Error Handling Patterns

- Use `with` for chaining operations that may fail:
  ```elixir
  with {:ok, participant} <- get_participant(id),
       {:ok, accounts} <- get_accounts(id) do
    {:ok, %{participant: participant, accounts: accounts}}
  end
  ```

- Map errors only at boundaries:
  - gRPC servers: convert to `GRPC.RPCError` with appropriate status codes
  - Binaries/CLIs: may raise at `main` level only
- Add context at boundaries, not deep inside core logic
- Prefer domain-specific error types inside services

### 4.4 Error Mapping at Boundaries

Convert domain errors to transport errors (HTTP/gRPC) in handlers:
- `:not_found` → `NOT_FOUND`
- `:account_exists` → `ALREADY_EXISTS`
- `{:insufficient_funds, _}` → `FAILED_PRECONDITION`
- Other errors → `INTERNAL`

Use exceptions only at boundaries (gRPC servers) when mapping to protocol errors.

---

## 5. Mnesia Patterns

### 5.1 Transactions

- **Always wrap Mnesia operations in transactions**:
  ```elixir
  result = :mnesia.transaction(fn ->
    # operations
  end)

  case result do
    {:atomic, value} -> {:ok, value}
    {:aborted, reason} -> {:error, reason}
  end
  ```

- Use `:mnesia.abort/1` to rollback with specific errors:
  ```elixir
  :mnesia.abort({:error, :not_found})
  ```

### 5.2 Table Records

- Records are tuples: `{table_name, key, field1, field2, ...}`
- First element is always the table name
- Second element is always the primary key

### 5.3 Schema Module

- All table names defined in `Scalegraph.Storage.Schema`
- Access via functions: `Schema.accounts_table()`
- **Never hardcode table names**
- Prefer idempotent table creation; migrations should be safe to run repeatedly
- In dev, initialize schema on startup; in prod, run via explicit admin/ops command or controlled startup step

### 5.4 Mnesia as Primary Database

- **Opinion**: **Mnesia is the single primary database for distributed Elixir systems.**
- Distributed, in-memory database built into OTP
- ACID transactions, secondary indices, table fragmentation
- Clean Elixir integration via `:mnesia` module

---

## 6. gRPC Patterns

### 6.1 Server Implementations

- **One server module per service**
- Use `raise GRPC.RPCError` for errors with appropriate status codes:
  ```elixir
  raise GRPC.RPCError, status: :not_found, message: "Account not found"
  ```

- Convert internal `{:error, reason}` tuples to gRPC status codes:
  - `:not_found` → `NOT_FOUND`
  - `:account_exists` → `ALREADY_EXISTS`
  - `{:insufficient_funds, _}` → `FAILED_PRECONDITION`
  - Other errors → `INTERNAL`

### 6.2 Proto Conversions

- Internal structs use maps with atom keys
- Proto messages use specific types
- Conversion helpers use `_to_proto` suffix (e.g., `account_to_proto/1`, `participant_to_proto/1`)

### 6.3 Error Handling in gRPC Servers

- Business errors (expected conditions) are returned as gRPC error tuples and logged at info level
- System errors (unexpected conditions) are raised as exceptions and logged at error level
- Example pattern:
  ```elixir
  defp business_error(status, message) do
    Logger.info("Business error [#{status}]: #{message}")
    {:error, GRPC.RPCError.exception(status: status, message: message)}
  end

  defp system_error(context, reason) do
    raise GRPC.RPCError, status: :internal, message: "#{context}: #{inspect(reason)}"
  end
  ```

---

## 7. Domain Conventions

### 7.1 IDs

- Participant IDs: `snake_case` strings (e.g., `"beauty_hosting"`)
- Account IDs: `"{participant_id}:{account_type}"` (e.g., `"seb:operating"`)
- Transaction IDs: Random hex strings (16 bytes)

### 7.2 Participant Roles

Valid roles (defined in `Schema.participant_roles/0`):
- `:access_provider`
- `:banking_partner`
- `:ecosystem_partner`
- `:supplier`
- `:equipment_provider`

### 7.3 Account Types

- `:standalone` - Not linked to a participant
- `:operating` - Main operating account
- `:receivables` - For incoming payments
- `:payables` - For outgoing payments
- `:escrow` - Held funds
- `:fees` - Fee collection
- `:usage` - Pay-per-use tracking

### 7.4 Amounts

- Always integers (representing smallest currency unit)
- Positive = credit, Negative = debit
- No floating point

---

## 8. Testing Strategy

### 8.1 Unit Tests

- Required for every module
- Use `ExUnit` with descriptive `describe` blocks
- Use property-based testing with `StreamData` for generative tests

### 8.2 Test Structure

```elixir
defmodule Scalegraph.Module.NameTest do
  use ExUnit.Case

  setup do
    # Setup code
    :ok
  end

  describe "function_name/arity" do
    test "describes expected behavior" do
      # test code
    end
  end
end
```

### 8.3 Integration Tests

- Use `ExUnit` tags (e.g., `@tag :integration`) for tests with external services
- Standup ephemeral Mnesia instances
- Clear Mnesia tables in setup when needed (use `Scalegraph.Storage.Schema.clear_all/0`)

### 8.4 API Contract Tests

- Test gRPC proto compliance

---

## 9. Code Quality & Engineering Habits

### 9.1 Code Style Tools

Always enable formatter & credo checks:
```bash
mix format --check-formatted
mix credo --strict
```

### 9.2 Concurrency & Processes

- Never hold locks across message receives (use `receive` with timeouts)
- Use OTP primitives (`GenServer`, `Agent`, `Task`) in production code; avoid raw `spawn`
- Spawn tasks only when concurrency is required; keep flow structured
- Add timeouts around external calls (`Task.await/2` with timeout, or `Process.send_after/3`)
- All long-running processes must be supervised

### 9.3 Avoiding Bad Patterns

- No business logic in controllers/handlers; handlers extract/validate/map only
- No scattered DB queries; repositories own data access
- Parameterize DB queries; avoid string interpolation
- Avoid `if Application.get_env/3` branches in production code; use dependency injection via function parameters or config
- Never hardcode table names; use schema module functions

---

## 10. Configuration & Secrets

### 10.1 Config Management

Use Elixir's built-in `Config` module + layered approach:
1. `config/config.exs` (base)
2. `config/dev.exs`, `config/prod.exs` (env-specific)
3. Environment variables via `System.get_env/1`
4. Runtime config via `config/runtime.exs`
5. Secrets store overrides

### 10.2 Secret Storage

- No plain `.env` files for production
- Use appropriate secrets management for your deployment environment

---

## 11. Deployment

### 11.1 Mix Tasks & Justfile

**Opinion**: Every repo **must** have a `Justfile` with:
```makefile
default: fmt lint test

fmt:
    mix format

lint:
    mix credo --strict

test:
    mix test

run:
    iex -S mix

build:
    MIX_ENV=prod mix release
```

### 11.2 Releases

- Use `mix release` for production deployments
- Never run `mix` commands in production
- **Opinion**: **All production deployments use releases.**

---

## 12. Using LLMs for Elixir (House Style)

Given a modern, high‑capability model, use it as a senior Elixir collaborator. Be explicit about constraints and ask for production‑grade outcomes.

### 12.1 Always Request Production‑Grade Output

- Ask for **"opinionated, production‑grade"** solutions
- Specify hard constraints in the prompt:
  - no `raise`, no `throw`, no exceptions in domain logic
  - structured, domain‑level error tuples
  - `Logger` or `Telemetry` everywhere (structured logging)
  - gRPC + OTP stack
  - Elixir 1.17+ and OTP 27+ assumptions
- Example prompt:
  > "Refactor this into an opinionated, production‑grade Elixir service: no raise/panic, structured error tuples, logging, gRPC."

### 12.2 Prefer Refactoring Over Greenfield

- Use the model to improve existing code, not just generate new code
- Typical asks:
  - "Refactor this gRPC server into layers: server → service → repository."
  - "Introduce domain error tuples + map to gRPC status codes."
  - "Add structured logging per request and per DB call."
  - "Make this module testable with dependency injection."

### 12.3 Let It Propose Architecture, Then Review

- Ask the model to propose module boundaries, protocols, and data types
- Treat proposals as a draft architecture you review and adjust
- Example prompt:
  > "Design the module + protocol layout for this feature. Optimize for testability, layering, and clean domain types."

### 12.4 Promote Good Patterns Into This Document

- When an output matches house style (errors, gRPC layout, Mnesia patterns, etc.), copy it here
- Then tell the model to follow that style in future work
- Example prompt:
  > "Follow the patterns in CONVENTIONS.md for errors and layering."

---

## 13. Rust CLI (Cross-Language Conventions)

### 13.1 Code Organization

- `src/grpc/` - gRPC client code
- `src/ui/` - TUI components
- One module per logical component

### 13.2 Error Handling

- Use `anyhow::Result` for fallible operations
- Use `thiserror` for custom error types

---

## Conclusion

This document defines an **opinionated, modern Elixir engineering standard**—centered on OTP, Mnesia, gRPC, robust testing, strong typing, and clean API definitions.

Elixir 1.17+ + OTP 27+ + fault-tolerant architecture ensures long-term maintainability, reliability, performance, and ecosystem alignment.
