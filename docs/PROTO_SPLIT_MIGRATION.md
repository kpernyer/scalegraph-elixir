# Proto Split Migration Guide

## What Was Done

✅ **Proto files split into 4 files:**
1. `proto/common.proto` - Shared messages (Participant, Account, Transaction)
2. `proto/ledger.proto` - Core ledger operations
3. `proto/business-rules.proto` - Business contracts and rules
4. `proto/smart-contracts.proto` - Smart contracts and automation

✅ **Build scripts updated:**
- `cli/build.rs` - Now compiles all 4 proto files
- `mcp/build.rs` - Now compiles all 4 proto files

✅ **Documentation updated:**
- `proto/README.md` - Updated with new structure

## Next Steps

### 1. Regenerate Elixir Proto Files

The Elixir proto files need to be regenerated from the new split proto files:

```bash
# Install protoc-gen-elixir if not already installed
mix escript.install hex protobuf

# Generate Elixir code from all proto files
protoc --elixir_out=./lib/scalegraph/proto \
  --proto_path=./proto \
  proto/common.proto \
  proto/ledger.proto \
  proto/business-rules.proto \
  proto/smart-contracts.proto
```

This will generate new proto modules in `lib/scalegraph/proto/` with the new package structure:
- `Scalegraph.Proto.Common.*`
- `Scalegraph.Proto.Ledger.*`
- `Scalegraph.Proto.Business.*`
- `Scalegraph.Proto.Smartcontracts.*`

### 2. Update Elixir Code

The Elixir code will need to be updated to use the new proto module names:

#### Before (old structure):
```elixir
alias Scalegraph.Proto.Account
alias Scalegraph.Proto.Transaction
alias Scalegraph.Proto.LedgerService
```

#### After (new structure):
```elixir
alias Scalegraph.Proto.Common.Account
alias Scalegraph.Proto.Common.Transaction
alias Scalegraph.Proto.Ledger.LedgerService
```

#### Files that need updating:
- `lib/scalegraph/ledger/server.ex` - Update proto references
- `lib/scalegraph/participant/server.ex` - Update proto references
- `lib/scalegraph/business/server.ex` - Update proto references
- Any other files that reference proto modules

### 3. Update Service Implementations

The service implementations need to reference the new proto modules:

```elixir
# Old
use GRPC.Server, service: Scalegraph.Proto.LedgerService.Service

# New
use GRPC.Server, service: Scalegraph.Proto.Ledger.LedgerService.Service
```

### 4. Test the Changes

1. **Test Rust CLI:**
   ```bash
   cd cli
   cargo build
   ```

2. **Test Rust MCP:**
   ```bash
   cd mcp
   cargo build
   ```

3. **Test Elixir Server:**
   ```bash
   mix compile
   mix test
   ```

### 5. Update Old Proto File (Optional)

You can either:
- **Option A**: Keep `proto/ledger.proto` as a legacy file (not recommended)
- **Option B**: Delete `proto/ledger.proto` and use only the new split files (recommended)

If deleting, make sure all references are updated first.

## Account Types Documentation

The account types are now documented in `common.proto` with their usage:

- **operating**: Likvida medel, dagligt kassaflöde (All participants)
- **escrow**: Fryst kapital (säkerhet, depå) (Bankers)
- **receivables**: Fordringar (framtida inbetalningar) (Suppliers, Bankers)
- **payables**: Skulder (framtida utbetalningar) (Salons, Suppliers)
- **fees**: Ackumulerad avgift/provision att samla in (Access Providers, Platforms)
- **usage**: Ackumulerad användningsavgift (Equipment Providers)

## Smart Contracts

The smart contracts proto file includes all the contract types you mentioned:

1. **Loan Contract** - With repayment schedule and auto-execute
2. **Invoice Contract** - With due dates, late fees, and auto-debit
3. **Subscription Contract** - With billing dates and auto-debit
4. **Conditional Payment** - With trigger conditions
5. **Revenue Share Contract** - With auto-split functionality

These are ready to be implemented in the Business/Contract layer.

## Troubleshooting

### Import Errors

If you get import errors, make sure:
1. All proto files are in the `proto/` directory
2. Import paths are correct (e.g., `import "common.proto"`)
3. Build scripts include all proto files

### Module Not Found

If Elixir can't find proto modules:
1. Regenerate proto files (see step 1)
2. Check that `lib/scalegraph/proto/` contains the generated files
3. Restart the Elixir application

### Build Failures

If Rust builds fail:
1. Check that all proto files exist
2. Verify import statements are correct
3. Make sure `tonic_build` can find all proto files

## Summary

The proto split is complete at the file level. The next steps are:
1. ✅ Proto files created
2. ✅ Build scripts updated
3. ⏳ Regenerate Elixir proto files
4. ⏳ Update Elixir code to use new module names
5. ⏳ Test everything works

Once these steps are complete, you'll have a clean three-layer architecture with proper separation of concerns!

