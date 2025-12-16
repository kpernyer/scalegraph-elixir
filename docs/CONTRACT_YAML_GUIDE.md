# Smart Contract YAML Guide

This guide explains how to create smart contracts using YAML format.

## Quick Start

### 1. Create a YAML Contract File

Create a file `my_contract.yaml`:

```yaml
name: "My Contract"
description: "Contract description"
type: supplier_registration
status: active

conditions:
  - type: time
    parameters:
      expires_at: ${expires_at}

actions:
  - type: transfer
    parameters:
      from_account: "${supplier_id}:operating"
      to_account: "${orchestrator_id}:fees"
      amount_cents: 5000
      reference: "REGISTRATION_FEE"

metadata:
  supplier_id: "${supplier_id}"
  orchestrator_id: "${orchestrator_id}"
```

### 2. Load the Contract

```bash
mix scalegraph.contract.load my_contract.yaml \
  --variables supplier_id=supplier_123 \
  --variables orchestrator_id=beauty_hosting
```

### 3. View in CLI

Your contract will now appear in the CLI's "Future" tab (if it has scheduled execution) and in participant detail views.

## Why YAML Contracts?

**Benefits:**
- ✅ No code changes needed for new contract types
- ✅ Version controlled contract definitions
- ✅ Self-documenting format
- ✅ Easy to test and iterate
- ✅ Reusable templates

**All contracts are stored the same way** - whether created from YAML or code, they're stored in the same database table and work identically.

## Your Existing Contracts

Your contracts (`a317e99d573a0a865cb55e37b9f5b47d` and others) **are in the database**. They're just not showing in the CLI because:

1. ✅ **Fixed**: gRPC server now exists and is running
2. ✅ **Fixed**: Generic contract support added to proto
3. ✅ **Fixed**: CLI now handles generic contracts

**To see your contracts:**
1. Restart the server (to load the new gRPC server)
2. Refresh the CLI (press `r` in the Future tab)
3. Your contracts should now appear!

## Converting Existing Contracts to YAML

You can export existing contracts to YAML format:

```elixir
alias Scalegraph.SmartContracts.Core

# Get your contract
{:ok, contract} = Core.get_contract("a317e99d573a0a865cb55e37b9f5b47d")

# The YAML source is stored in metadata
yaml_source = Map.get(contract.metadata || %{}, "yaml_source", "")
IO.puts(yaml_source)
```

## See Also

- `docs/GENERIC_CONTRACTS.md` - Full documentation
- `examples/contracts/` - Example YAML contracts
- `lib/scalegraph/smart_contracts/yaml_parser.ex` - Parser implementation

