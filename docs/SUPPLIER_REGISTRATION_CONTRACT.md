# Supplier Registration Contract

This document describes the supplier registration smart contract for suppliers joining the ecosystem.

## Contract Terms

- **Registration Fee**: 50 EUR (5000 cents) - one-time payment to ecosystem orchestrator
- **Monthly Fee**: 100 EUR (10000 cents) per month
  - Starts when first ecosystem provider uses the supplier's service
  - 90% (9000 cents) goes to orchestrator
  - 10% (1000 cents) goes to the first ecosystem provider that used the service
- **Validity Period**: 1 year from contract creation
- **Automatic Billing**: Monthly fees are automatically charged on the 1st of each month

## Usage

### Prerequisites

1. Ensure the server is running:
   ```bash
   mix run --no-halt
   ```

2. Ensure you have:
   - A supplier participant (role: `:supplier`)
   - An ecosystem orchestrator participant (role: `:ecosystem_orchestrator`)
   - Supplier must have an `operating` account with sufficient balance

### Create a Supplier Registration Contract

```elixir
alias Scalegraph.SmartContracts.Core

# Create a supplier registration contract
{:ok, contract} = Core.create_supplier_registration_contract("supplier_123")

# The registration fee (50 EUR) is charged immediately
```

**What happens:**
- Contract is created with status `:active`
- Registration fee of 50 EUR is immediately transferred from `supplier_123:operating` to `orchestrator:fees`
- Monthly fee billing is set up but not yet active (waits for first provider usage)
- Contract expires after 1 year

### Trigger Monthly Fee (When First Provider Uses Service)

When an ecosystem provider first uses the supplier's service, trigger the monthly fee:

```elixir
# When first ecosystem provider uses the supplier's service
{:ok, :started} = Core.trigger_supplier_monthly_fee("supplier_123", "ecosystem_provider_456")
```

**What happens:**
- First monthly fee (100 EUR) is charged immediately
- 90 EUR goes to orchestrator's fees account
- 10 EUR goes to the first provider's operating account
- Monthly billing is activated for future months
- Future monthly fees will be charged automatically on the 1st of each month

### Get Contract Information

```elixir
# Get the supplier registration contract
{:ok, contract} = Core.get_supplier_registration_contract("supplier_123")

# Inspect contract details
IO.inspect(contract.metadata)
# %{
#   "supplier_id" => "supplier_123",
#   "orchestrator_id" => "beauty_hosting",
#   "registration_fee_cents" => 5000,
#   "monthly_fee_cents" => 10000,
#   "created_at" => 1234567890000,
#   "expires_at" => 1238256000000,
#   "first_provider_id" => "ecosystem_provider_456",
#   "monthly_fee_started" => true,
#   "monthly_fee_started_at" => 1234567891000,
#   "last_monthly_fee_at" => 1234567891000
# }
```

### Check Contract Status

```elixir
# Get contract by ID
{:ok, contract} = Core.get_contract(contract_id)

# Check if monthly fee has started
metadata = contract.metadata || %{}
if Map.get(metadata, "monthly_fee_started", false) do
  IO.puts("Monthly fees are active")
  IO.puts("First provider: #{Map.get(metadata, "first_provider_id")}")
else
  IO.puts("Monthly fees not yet started - waiting for first provider usage")
end

# Check if contract has expired
now = System.system_time(:millisecond)
expires_at = Map.get(metadata, "expires_at", 0)
if now >= expires_at do
  IO.puts("Contract has expired")
else
  days_remaining = div(expires_at - now, 24 * 60 * 60 * 1000)
  IO.puts("Contract expires in #{days_remaining} days")
end
```

### Automatic Monthly Billing

The contract is automatically scheduled to execute monthly fees on the 1st of each month. The scheduler (`Scalegraph.SmartContracts.Scheduler`) runs every minute and executes contracts whose conditions are met.

**Monthly Fee Execution:**
- Only executes if monthly fee has been started (first provider has used the service)
- Only executes once per month (tracks `last_monthly_fee_at`)
- Automatically stops after contract expiration (1 year)
- Splits payment: 90% to orchestrator, 10% to first provider

### Manual Execution

You can manually trigger contract execution (useful for testing):

```elixir
# Execute the contract manually
{:ok, result} = Core.execute_contract(contract_id)

# Returns:
# %{
#   executed: true,
#   transaction_ids: ["tx1", "tx2"]
# }
```

## Example Script

A complete example script is available at:
```
scripts/supplier_registration_example.exs
```

Run it with:
```bash
mix run scripts/supplier_registration_example.exs
```

## Integration Points

### When to Trigger Monthly Fee

The monthly fee should be triggered when:
- An ecosystem provider first purchases from the supplier
- An ecosystem provider first subscribes to the supplier's service
- Any first-time transaction between an ecosystem provider and the supplier occurs

Example integration in business logic:

```elixir
defmodule Scalegraph.Business.Transactions do
  def purchase_invoice(supplier_id, buyer_id, amount, reference, opts \\ []) do
    # Check if buyer is an ecosystem provider
    case Participant.Core.get_participant(buyer_id) do
      {:ok, %{role: :ecosystem_partner}} ->
        # Check if supplier has a registration contract
        case SmartContracts.Core.get_supplier_registration_contract(supplier_id) do
          {:ok, contract} ->
            metadata = contract.metadata || %{}
            # Trigger monthly fee if not already started
            if not Map.get(metadata, "monthly_fee_started", false) do
              SmartContracts.Core.trigger_supplier_monthly_fee(supplier_id, buyer_id)
            end
          {:error, :not_found} ->
            # No registration contract - supplier not registered
            :ok
        end
      _ ->
        :ok
    end
    
    # Continue with invoice creation...
  end
end
```

## Error Handling

Common errors:

- `{:error, :orchestrator_not_found}` - No ecosystem orchestrator found in the system
- `{:error, :supplier_not_found}` - Supplier participant doesn't exist
- `{:error, {:invalid_role, ...}}` - Participant is not a supplier
- `{:error, {:registration_fee_failed, reason}}` - Registration fee payment failed (insufficient funds)
- `{:error, :contract_not_found}` - No registration contract found for supplier
- `{:error, :already_started}` - Monthly fee already started (idempotent)

## Account Requirements

The supplier must have:
- An `operating` account with sufficient balance for:
  - Registration fee: 50 EUR (5000 cents)
  - Monthly fees: 100 EUR (10000 cents) per month

The orchestrator must have:
- A `fees` account (created automatically if it doesn't exist)

The first ecosystem provider must have:
- An `operating` account (receives 10% of monthly fees)

## Contract Lifecycle

1. **Creation**: Contract created, registration fee charged immediately
2. **Waiting**: Contract active, waiting for first provider usage
3. **Active**: Monthly fees started, billing monthly
4. **Expired**: Contract expires after 1 year, status changes to `:completed`

## Notes

- The contract automatically expires after 1 year
- Monthly fees only start when first ecosystem provider uses the service
- The first provider that triggers monthly fees receives 10% of all future monthly fees
- All monthly fees are split 90/10 between orchestrator and first provider
- The contract can be queried but cannot be modified after creation

