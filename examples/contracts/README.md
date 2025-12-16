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

- `supplier_registration.yaml` - Supplier registration with registration fee and monthly fees

