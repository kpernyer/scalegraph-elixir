# Smart Contract YAML Examples

This directory contains example YAML contract definitions that can be used to create smart contracts.

## Usage

### From Elixir Code

```elixir
alias Scalegraph.SmartContracts.YamlParser

# Parse and create from YAML string
yaml_content = """
name: "My Contract"
type: supplier_registration
conditions:
  - type: time
    parameters:
      expires_at: 1234567890000
actions:
  - type: transfer
    parameters:
      from_account: "supplier:operating"
      to_account: "orchestrator:fees"
      amount_cents: 5000
"""

variables = %{
  "supplier_id" => "supplier_123",
  "orchestrator_id" => "beauty_hosting",
  "created_at" => System.system_time(:millisecond),
  "expires_at" => System.system_time(:millisecond) + (365 * 24 * 60 * 60 * 1000)
}

{:ok, contract} = YamlParser.parse_and_create(yaml_content, variables: variables)

# Or parse from file
{:ok, contract} = YamlParser.parse_file_and_create("examples/contracts/supplier_registration.yaml", 
  variables: variables
)
```

### From Mix Task

```bash
# Create a mix task to load contracts from YAML files
mix scalegraph.contract.load examples/contracts/supplier_registration.yaml
```

## YAML Contract Format

### Required Fields

- `name` - Contract name (string)
- `type` - Contract type (string or atom): `supplier_registration`, `subscription`, `invoice`, etc.

### Optional Fields

- `description` - Contract description (string)
- `status` - Contract status: `active`, `paused`, `completed`, `cancelled` (default: `active`)
- `conditions` - List of conditions (array)
- `actions` - List of actions (array)
- `metadata` - Additional metadata (map)

### Conditions

Conditions determine when a contract should execute:

```yaml
conditions:
  - type: time
    parameters:
      expires_at: 1234567890000
      first_payment_date: 1234567890000
      payment_interval_ms: 2592000000
      total_payments: 12
  
  - type: balance
    parameters:
      account_id: "supplier:operating"
      min_balance: 10000
  
  - type: event
    parameters:
      event_type: "first_provider_usage"
      supplier_id: "supplier_123"
```

### Actions

Actions define what happens when conditions are met:

```yaml
actions:
  - type: transfer
    parameters:
      from_account: "supplier:operating"
      to_account: "orchestrator:fees"
      amount_cents: 5000
      reference: "SUPPLIER_REGISTRATION_FEE"
  
  - type: supplier_monthly_fee
    parameters:
      supplier_id: "supplier_123"
      orchestrator_id: "beauty_hosting"
      monthly_fee_cents: 10000
      orchestrator_share: 0.9
      first_provider_share: 0.1
```

### Variable Substitution

You can use `${variable_name}` syntax for variable substitution:

```yaml
name: "Contract for ${supplier_id}"
metadata:
  supplier_id: "${supplier_id}"
  created_at: "${created_at}"
```

Variables are provided when parsing:

```elixir
YamlParser.parse_and_create(yaml_content, 
  variables: %{
    "supplier_id" => "supplier_123",
    "created_at" => System.system_time(:millisecond)
  }
)
```

## Example Contracts

This directory contains the following example contracts:

### Core Contract Types

1. **`supplier_registration.yaml`** - Supplier registration with registration fee and monthly fees
   - One-time registration fee (50 EUR)
   - Monthly fees triggered when first provider uses service
   - 90/10 revenue split (orchestrator/provider)

2. **`monthly_subscription.yaml`** - Recurring monthly subscription payments
   - Time-based recurring payments
   - Configurable payment interval and total payments
   - Automatic subscription management

3. **`loan_with_repayment.yaml`** - Loan contract with scheduled repayments
   - Principal amount with interest
   - Monthly repayment schedule
   - Automatic repayment tracking

4. **`invoice_auto_payment.yaml`** - Invoice with automatic payment on due date
   - Time-based payment trigger (due date)
   - Balance check before payment
   - Automatic invoice settlement

5. **`revenue_share.yaml`** - Revenue sharing between parties
   - Percentage-based revenue split
   - Event-triggered distribution
   - Multi-party revenue sharing

6. **`conditional_payment.yaml`** - Payment triggered by specific conditions
   - Multiple condition types (time, balance, event)
   - Event-driven execution
   - Conditional logic

7. **`ecosystem_partner_membership.yaml`** - Membership contract for ecosystem partners
   - One-time membership fee
   - Optional monthly membership fees
   - Partner type management

8. **`simple_transfer.yaml`** - Basic one-time transfer example
   - Simple transfer between accounts
   - Minimal configuration
   - Good starting point for learning

## Quick Start Examples

### Loading a Subscription Contract

```bash
# Calculate dates (1 year subscription, starting today)
NOW=$(date +%s)000
FIRST_PAYMENT=$NOW
EXPIRES=$((NOW + 365*24*60*60*1000))

mix scalegraph.contract.load examples/contracts/monthly_subscription.yaml \
  --variables subscriber_id=alice \
  --variables provider_id=beauty_hosting \
  --variables service_name="Premium Beauty Services" \
  --variables monthly_amount_cents=5000 \
  --variables total_payments=12 \
  --variables first_payment_date=$FIRST_PAYMENT \
  --variables expires_at=$EXPIRES \
  --variables created_at=$NOW
```

### Loading a Loan Contract

```bash
NOW=$(date +%s)000
FIRST_PAYMENT=$((NOW + 30*24*60*60*1000))  # 30 days from now
LOAN_END=$((NOW + 12*30*24*60*60*1000))  # 12 months from now

mix scalegraph.contract.load examples/contracts/loan_with_repayment.yaml \
  --variables loan_id=loan_001 \
  --variables lender_id=bank_001 \
  --variables borrower_id=alice \
  --variables principal_cents=100000 \
  --variables monthly_payment_cents=9000 \
  --variables interest_rate=0.05 \
  --variables num_payments=12 \
  --variables first_payment_date=$FIRST_PAYMENT \
  --variables loan_end_date=$LOAN_END \
  --variables created_at=$NOW
```

### Loading an Invoice Auto-Payment

```bash
NOW=$(date +%s)000
DUE_DATE=$((NOW + 30*24*60*60*1000))  # 30 days from now

mix scalegraph.contract.load examples/contracts/invoice_auto_payment.yaml \
  --variables invoice_id=inv_001 \
  --variables supplier_id=supplier_001 \
  --variables buyer_id=alice \
  --variables invoice_amount_cents=50000 \
  --variables issue_date=$NOW \
  --variables due_date=$DUE_DATE \
  --variables payment_terms="Net 30" \
  --variables created_at=$NOW
```

