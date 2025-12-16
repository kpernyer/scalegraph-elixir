# Smart Contract Examples

This document describes reusable smart contract examples for common marketplace scenarios.

## Marketplace Membership Contract

The marketplace membership contract is a subscription-based contract that automatically charges all ecosystem participants a monthly membership fee.

### Contract Terms

- **Cost**: 60 EUR per month (6000 cents) per participant
- **First Payment**: 3 months after joining the marketplace (grace period)
- **Payment Schedule**: Monthly for 9 months after first payment
- **Total Payments**: 10 payments per participant (1 after grace period + 9 monthly)
- **Renewal Deadline**: All actors must accept renewal 30 days before contract termination

### Usage

#### Create a Marketplace Membership Contract

```elixir
alias Scalegraph.SmartContracts.Examples

# Create contract with default settings (60 EUR/month, 3 month grace, 9 monthly payments)
{:ok, contract_info} = Examples.create_marketplace_membership("beauty_hosting")

# Or customize the contract
{:ok, contract_info} = Examples.create_marketplace_membership("beauty_hosting",
  monthly_fee_cents: 5000,        # 50 EUR per month
  grace_period_months: 2,          # 2 months grace period
  payment_months: 12,              # 12 monthly payments
  renewal_notice_days: 45,         # 45 days notice for renewal
  exclude_participants: ["test_participant"]  # Exclude specific participants
)
```

#### Get Contract Information

```elixir
# Get detailed contract information
{:ok, info} = Examples.get_marketplace_membership_info(contract_id)

# Returns:
# %{
#   contract_id: "abc123...",
#   status: :active,
#   marketplace_owner_id: "beauty_hosting",
#   participant_ids: ["salon_glamour", "schampo_etc", ...],
#   monthly_fee_cents: 6000,
#   total_payments: 10,
#   first_payment_date: 1717200000000,
#   contract_end_date: 1724889600000,
#   renewal_deadline: 1722297600000,
#   ...
# }
```

#### Calculate Next Payment Date

```elixir
# Get the timestamp when the next payment should occur
{:ok, next_payment_timestamp} = Examples.calculate_next_payment_date(contract_id)

# Format as readable date
Examples.format_date(next_payment_timestamp)
# => "2024-06-01 00:00:00Z"
```

#### Check Renewal Status

```elixir
# Check if renewal acceptance is required
{:ok, renewal_required} = Examples.check_renewal_required(contract_id)

if renewal_required do
  IO.puts("⚠️  All participants must accept renewal!")
end
```

#### Execute Payment Manually

```elixir
# Manually trigger a payment (normally done automatically by scheduler)
{:ok, result} = Examples.execute_membership_payment(contract_id)

# Returns:
# %{
#   executed: true,
#   transaction_ids: ["tx1", "tx2", ...],
#   payment_number: 1
# }
```

### Contract Structure

The marketplace membership contract consists of:

1. **Conditions**: Time-based conditions that determine when payments should occur
2. **Actions**: Transfer actions that move funds from each participant to the marketplace owner
3. **Schedule**: Cron-based schedule that checks daily for due payments

### Payment Flow

1. **Month 0-2**: Grace period (no payments)
2. **Month 3**: First payment (60 EUR from each participant)
3. **Months 4-12**: Monthly payments (60 EUR each month)
4. **Month 11**: Renewal deadline (30 days before contract end)
5. **Month 12**: Contract ends

### Example Script

A complete example script is available at:
```
scripts/marketplace_membership_example.exs
```

Run it with:
```bash
mix run scripts/marketplace_membership_example.exs
```

### Integration with Scheduler

The contract is automatically scheduled to check daily for due payments. The scheduler (`Scalegraph.SmartContracts.Scheduler`) runs every minute and executes contracts whose conditions are met.

### Contract Metadata

The contract stores detailed metadata including:
- Marketplace owner ID
- List of all participant IDs
- Payment schedule details
- Dates (first payment, end date, renewal deadline)
- Fee structure

This metadata can be accessed via `get_marketplace_membership_info/1`.

### Error Handling

Common errors:
- `{:error, :no_participants}` - No participants found (excluding orchestrator)
- `{:error, :not_found}` - Contract ID doesn't exist
- `{:error, :not_marketplace_membership}` - Contract exists but isn't a marketplace membership contract
- `{:error, :invalid_parameters}` - Invalid action parameters

### Customization Options

All contract parameters can be customized:

```elixir
Examples.create_marketplace_membership(marketplace_owner_id,
  monthly_fee_cents: 7500,        # 75 EUR per month
  grace_period_months: 6,          # 6 months grace period
  payment_months: 18,              # 18 monthly payments
  renewal_notice_days: 60,         # 60 days notice
  exclude_participants: ["participant1", "participant2"],
  metadata: %{
    "custom_field" => "custom_value"
  }
)
```

## Supplier Registration Contract

The supplier registration contract handles marketplace registration fees and monthly subscription fees for suppliers.

### Contract Terms

- **Registration Fee**: 50 EUR (5000 cents) - one-time payment to orchestrator
- **Monthly Fee**: 100 EUR (10000 cents) per month
  - Starts when first ecosystem provider uses the supplier's service
  - 90% (9000 cents) to orchestrator
  - 10% (1000 cents) to first provider
- **Validity Period**: 1 year from creation

### Usage

```elixir
alias Scalegraph.SmartContracts.Core

# Create a supplier registration contract
{:ok, contract} = Core.create_supplier_registration_contract("supplier_123")

# When first ecosystem provider uses the service
{:ok, :started} = Core.trigger_supplier_monthly_fee("supplier_123", "ecosystem_provider_456")

# Get contract information
{:ok, contract} = Core.get_supplier_registration_contract("supplier_123")
```

### Example Script

A complete example script is available at:
```
scripts/supplier_registration_example.exs
```

Run it with:
```bash
mix run scripts/supplier_registration_example.exs
```

For detailed documentation, see: [Supplier Registration Contract Guide](SUPPLIER_REGISTRATION_CONTRACT.md)

## Ecosystem Partner Membership Contract

The ecosystem partner membership contract automatically manages payments between the ecosystem orchestrator and ecosystem partners. When a new ecosystem partner accepts the rules of the ecosystem, they are automatically added to this contract.

### Contract Terms

- **Cost**: 50 EUR per month (5000 cents) per ecosystem partner
- **First Payment**: 1 month after joining (grace period)
- **Payment Schedule**: Monthly for 11 months after first payment
- **Total Payments**: 12 payments per partner (1 after grace period + 11 monthly)
- **Automatic Addition**: New partners are added when they accept the rules

### Usage

#### Accept Ecosystem Rules (Add Partner to Contract)

When a new ecosystem partner accepts the rules, they are automatically added to the membership contract:

```elixir
alias Scalegraph.SmartContracts.Examples

# Partner accepts rules and is added to the contract
{:ok, contract} = Examples.accept_ecosystem_rules("new_salon", "beauty_hosting")

# Or let the system find the orchestrator automatically
{:ok, contract} = Examples.accept_ecosystem_rules("new_salon")
```

#### Create the Initial Contract

The contract is automatically created when the first partner accepts rules, but you can also create it explicitly:

```elixir
# Create contract with default settings (50 EUR/month, 1 month grace, 11 monthly payments)
{:ok, contract} = Examples.create_ecosystem_partner_membership("beauty_hosting")

# Or customize the contract
{:ok, contract} = Examples.create_ecosystem_partner_membership("beauty_hosting",
  monthly_fee_cents: 6000,        # 60 EUR per month
  grace_period_months: 2,          # 2 months grace period
  payment_months: 12,              # 12 monthly payments
  metadata: %{
    "contract_version" => "1.0"
  }
)
```

#### Get Contract Information

```elixir
alias Scalegraph.SmartContracts.Core

# Get the contract for an orchestrator
{:ok, contract} = Core.get_or_create_ecosystem_partner_membership_contract("beauty_hosting")

# Access contract metadata
partner_ids = contract.metadata["partner_ids"]
monthly_fee = contract.metadata["monthly_fee_cents"]
```

### How It Works

1. **Contract Creation**: The contract is created by the ecosystem orchestrator (or automatically when the first partner accepts rules)

2. **Partner Addition**: When an ecosystem partner accepts the rules:
   - The system finds or creates the membership contract
   - The partner is added to the contract's participant list
   - A payment action is created for the new partner
   - The partner's operating account is created if it doesn't exist

3. **Automatic Payments**: The contract executes monthly (on the 1st of each month) and charges all partners in the contract

4. **Payment Flow**:
   - Each partner's operating account is debited
   - The orchestrator's fees account is credited
   - All payments happen automatically via the smart contract scheduler

### Integration

The contract integrates with:
- **Participant Management**: Automatically creates accounts for new partners
- **Smart Contract Scheduler**: Executes payments monthly
- **Ledger**: Records all payment transactions

### Example Workflow

```elixir
# 1. Create the initial contract (optional - will be created automatically)
{:ok, contract} = Examples.create_ecosystem_partner_membership("beauty_hosting")

# 2. New partner accepts rules and is added
{:ok, updated_contract} = Examples.accept_ecosystem_rules("salon_glamour", "beauty_hosting")

# 3. Another partner accepts rules
{:ok, updated_contract} = Examples.accept_ecosystem_rules("studio_solveig", "beauty_hosting")

# 4. Contract automatically executes monthly payments for all partners
# (handled by Scalegraph.SmartContracts.Scheduler)
```

## Future Examples

Additional contract examples will be added for:
- Revenue share contracts
- Conditional payment contracts
- Loan automation contracts
- Subscription service contracts

