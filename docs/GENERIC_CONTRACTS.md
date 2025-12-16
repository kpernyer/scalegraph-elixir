# Generic Smart Contracts (YAML-based)

The Scalegraph smart contracts system supports a **generic YAML-based contract format** that provides maximum flexibility for defining contracts without requiring code changes.

## Overview

Instead of hardcoding specific contract types, you can define contracts in YAML format. This allows you to:
- Create new contract types without modifying code
- Version control contract definitions
- Easily share and reuse contract templates
- Make contracts self-documenting

## YAML Contract Format

### Basic Structure

```yaml
name: "Contract Name"
description: "Contract description"
type: supplier_registration  # Contract type
status: active  # active, paused, completed, cancelled

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
      reference: "SUPPLIER_REGISTRATION_FEE"

metadata:
  supplier_id: "supplier_123"
  orchestrator_id: "beauty_hosting"
```

### Required Fields

- **`name`** (string) - Contract name
- **`type`** (string) - Contract type: `supplier_registration`, `subscription`, `invoice`, `generic`, etc.

### Optional Fields

- **`description`** (string) - Contract description
- **`status`** (string) - Contract status: `active`, `paused`, `completed`, `cancelled` (default: `active`)
- **`conditions`** (array) - List of conditions
- **`actions`** (array) - List of actions
- **`metadata`** (map) - Additional metadata

## Conditions

Conditions determine **when** a contract should execute. Multiple conditions can be combined (all must be met).

### Time Condition

```yaml
conditions:
  - type: time
    parameters:
      expires_at: 1234567890000  # Unix timestamp in milliseconds
      first_payment_date: 1234567890000
      payment_interval_ms: 2592000000  # 30 days
      total_payments: 12
```

### Balance Condition

```yaml
conditions:
  - type: balance
    parameters:
      account_id: "supplier:operating"
      min_balance: 10000
```

### Event Condition

```yaml
conditions:
  - type: event
    parameters:
      event_type: "first_provider_usage"
      supplier_id: "supplier_123"
```

## Actions

Actions define **what happens** when conditions are met.

### Transfer Action

```yaml
actions:
  - type: transfer
    parameters:
      from_account: "supplier:operating"
      to_account: "orchestrator:fees"
      amount_cents: 5000
      reference: "SUPPLIER_REGISTRATION_FEE"
```

### Custom Actions

```yaml
actions:
  - type: supplier_monthly_fee
    parameters:
      supplier_id: "supplier_123"
      orchestrator_id: "beauty_hosting"
      monthly_fee_cents: 10000
      orchestrator_share: 0.9
      first_provider_share: 0.1
```

## Variable Substitution

Use `${variable_name}` syntax for dynamic values:

```yaml
name: "Supplier Registration: ${supplier_id}"
metadata:
  supplier_id: "${supplier_id}"
  created_at: "${created_at}"
  expires_at: "${expires_at}"
```

Variables are provided when creating the contract:

```elixir
YamlParser.parse_and_create(yaml_content, 
  variables: %{
    "supplier_id" => "supplier_123",
    "created_at" => System.system_time(:millisecond),
    "expires_at" => System.system_time(:millisecond) + (365 * 24 * 60 * 60 * 1000)
  }
)
```

## Usage

### From Elixir Code

```elixir
alias Scalegraph.SmartContracts.YamlParser

# From YAML string
{:ok, contract} = YamlParser.parse_and_create(yaml_content, 
  variables: %{"supplier_id" => "supplier_123"}
)

# From YAML file
{:ok, contract} = YamlParser.parse_file_and_create("contracts/my_contract.yaml",
  variables: %{"supplier_id" => "supplier_123"}
)
```

### From Mix Task

```bash
# Load contract from YAML file
mix scalegraph.contract.load examples/contracts/supplier_registration.yaml \
  --variables supplier_id=supplier_123 \
  --variables orchestrator_id=beauty_hosting
```

### From gRPC

```elixir
# Via gRPC client
request = %CreateGenericContractRequest{
  yaml_content: yaml_string,
  variables: %{"supplier_id" => "supplier_123"}
}
client.create_generic_contract(request)
```

## Example: Supplier Registration Contract

See `examples/contracts/supplier_registration.yaml` for a complete example.

## Benefits

1. **Flexibility** - Create any contract type without code changes
2. **Version Control** - Contract definitions are versioned in Git
3. **Reusability** - Share contract templates across projects
4. **Documentation** - YAML is self-documenting
5. **Testing** - Easy to test different contract configurations

## Contract Storage

All contracts (whether created from YAML or code) are stored in the same database table (`scalegraph_smart_contracts`). The YAML source is stored in the contract's metadata for reference.

## CLI Display

Generic contracts appear in the CLI's "Future" tab with:
- Contract name and description
- Contract type (e.g., "Generic (supplier_registration)")
- Next execution time (calculated from conditions)

## See Also

- `examples/contracts/` - Example YAML contract definitions
- `lib/scalegraph/smart_contracts/yaml_parser.ex` - YAML parser implementation
- `lib/mix/tasks/scalegraph.contract.load.ex` - Mix task for loading contracts

