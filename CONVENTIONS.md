# Coding Conventions

## Elixir Style

### Module Structure

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

### Naming Conventions

- **Modules**: `PascalCase` (e.g., `Scalegraph.Ledger.Core`)
- **Functions**: `snake_case` (e.g., `create_account`)
- **Variables**: `snake_case` (e.g., `account_id`)
- **Module Attributes**: `@snake_case` (e.g., `@accounts_table`)
- **Atoms**: `snake_case` (e.g., `:account_exists`)

### Function Arguments

- Use guard clauses for type validation:
  ```elixir
  def create_account(id, balance) when is_binary(id) and is_integer(balance) do
  ```

- Default arguments use `\\`:
  ```elixir
  def create_account(id, balance \\ 0, metadata \\ %{})
  ```

### Return Values

- Success: `{:ok, result}`
- Error: `{:error, reason}` or `{:error, {type, message}}`
- Never return raw values for operations that can fail

### Pattern Matching

- Prefer pattern matching in function heads over conditionals
- Use `case` for matching on single values
- Use `with` for chaining operations that may fail:
  ```elixir
  with {:ok, participant} <- get_participant(id),
       {:ok, accounts} <- get_accounts(id) do
    {:ok, %{participant: participant, accounts: accounts}}
  end
  ```

## Mnesia Patterns

### Transactions

- Always wrap Mnesia operations in transactions:
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

### Table Records

- Records are tuples: `{table_name, key, field1, field2, ...}`
- First element is always the table name
- Second element is always the primary key

### Schema Module

- All table names defined in `Scalegraph.Storage.Schema`
- Access via functions: `Schema.accounts_table()`
- Never hardcode table names

## gRPC Patterns

### Server Implementations

- One server module per service
- Use `raise GRPC.RPCError` for errors:
  ```elixir
  raise GRPC.RPCError, status: :not_found, message: "Account not found"
  ```

### Proto Conversions

- Internal structs use maps with atom keys
- Proto messages use specific types
- Conversion helpers: `_to_proto` suffix

## Domain Conventions

### IDs

- Participant IDs: `snake_case` strings (e.g., `"beauty_hosting"`)
- Account IDs: `"{participant_id}:{account_type}"` (e.g., `"seb:operating"`)
- Transaction IDs: Random hex strings (16 bytes)

### Participant Roles

Valid roles (defined in `Schema.participant_roles/0`):
- `:access_provider`
- `:banking_partner`
- `:ecosystem_partner`
- `:supplier`
- `:equipment_provider`

### Account Types

- `:standalone` - Not linked to a participant
- `:operating` - Main operating account
- `:receivables` - For incoming payments
- `:payables` - For outgoing payments
- `:escrow` - Held funds
- `:fees` - Fee collection
- `:usage` - Pay-per-use tracking

### Amounts

- Always integers (representing smallest currency unit)
- Positive = credit, Negative = debit
- No floating point

## Testing

### Test Structure

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

### Test Isolation

- Clear Mnesia tables in setup when needed
- Use `Scalegraph.Storage.Schema.clear_all/0` for clean state

## Rust CLI

### Code Organization

- `src/grpc/` - gRPC client code
- `src/ui/` - TUI components
- One module per logical component

### Error Handling

- Use `anyhow::Result` for fallible operations
- Use `thiserror` for custom error types
