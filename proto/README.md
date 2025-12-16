# Protobuf Definitions

This directory contains the Protocol Buffer (protobuf) definitions for the Scalegraph Ledger gRPC API.

## Structure

The proto files are organized into three layers plus common messages:

- **`common.proto`** - Shared foundational messages (Participant, Account, Transaction)
- **`ledger.proto`** - Layer 1: Core ledger operations (pure double-entry bookkeeping)
- **`business-rules.proto`** - Layer 2: Business contracts and rules (invoices, loans, etc.)
- **`smart-contracts.proto`** - Layer 3: Smart contracts and automation

## Architecture

```
┌─────────────────────────────────────┐
│  smart-contracts.proto              │  ← Layer 3: Automation
│  (imports all below)                │
└─────────────────────────────────────┘
              │
┌─────────────────────────────────────┐
│  business-rules.proto               │  ← Layer 2: Business Rules
│  (imports common + ledger)          │
└─────────────────────────────────────┘
              │
┌─────────────────────────────────────┐
│  ledger.proto                       │  ← Layer 1: Core Ledger
│  (imports common)                   │
└─────────────────────────────────────┘
              │
┌─────────────────────────────────────┐
│  common.proto                       │  ← Shared Messages
│  (no imports)                       │
└─────────────────────────────────────┘
```

## Single Source of Truth

This `proto/` directory is the **single source of truth** for all protobuf definitions. All build systems reference this directory:

- **Elixir Server**: Uses all proto files in `proto/` directory
- **Rust CLI**: `cli/build.rs` reads from `../proto/*.proto`
- **Rust MCP**: `mcp/build.rs` reads from `../proto/*.proto`

## Building

### Rust Projects

Rust projects automatically generate code from the proto files during `cargo build`. The build scripts:
1. Read all proto files from `../proto/` in dependency order
2. Strip Elixir-specific options (like `elixir_module_prefix`)
3. Generate Rust code via `tonic_build`

### Elixir Server

The Elixir protobuf code in `lib/scalegraph/proto/` is manually generated from all proto files:

```bash
protoc --elixir_out=./lib/scalegraph/proto \
  --proto_path=./proto \
  proto/common.proto \
  proto/ledger.proto \
  proto/business-rules.proto \
  proto/smart-contracts.proto
```

## File Dependencies

- `common.proto` - No dependencies (foundational)
- `ledger.proto` - Imports `common.proto`
- `business-rules.proto` - Imports `common.proto` and `ledger.proto`
- `smart-contracts.proto` - Imports `common.proto`, `ledger.proto`, and `business-rules.proto`

## Adding New Proto Files

When adding new `.proto` files:
1. Add them to this `proto/` directory
2. Update `cli/build.rs` and `mcp/build.rs` to include them in the compilation
3. Update this README
4. Regenerate code for all platforms

## Notes

- The proto files include Elixir-specific options (e.g., `elixir_module_prefix`) which are automatically stripped by Rust build scripts
- All proto files should follow the `proto3` syntax
- Package names:
  - `scalegraph.common` - Common messages
  - `scalegraph.ledger` - Ledger service
  - `scalegraph.business` - Business rules service
  - `scalegraph.smartcontracts` - Smart contracts service

