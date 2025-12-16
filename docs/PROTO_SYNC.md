# Protobuf File Structure

## Overview

The Scalegraph project uses Protocol Buffers (protobuf) for gRPC communication. All protobuf definitions are stored in a **single source of truth**:

**`proto/ledger.proto`** - Single source of truth for all protobuf definitions

## Architecture

All build systems point to the same `proto/` directory at the project root:

- **Elixir Server**: Uses `proto/ledger.proto` directly (manual generation)
- **Rust CLI**: `cli/build.rs` reads from `../proto/ledger.proto`
- **Rust MCP**: `mcp/build.rs` reads from `../proto/ledger.proto`

## Build Process

### Rust Projects

Both `cli/` and `mcp/` have `build.rs` scripts that:
1. Read `../proto/ledger.proto`
2. Strip Elixir-specific options (like `elixir_module_prefix`)
3. Generate Rust code via `tonic_build`

This happens automatically during `cargo build`.

### Elixir Server

The Elixir protobuf code in `lib/scalegraph/proto/ledger.pb.ex` is manually generated from `proto/ledger.proto`.

## Workflow

1. **Edit the proto file**: `proto/ledger.proto` (single source of truth)
2. **Rebuild projects**: 
   - Elixir: `mix compile` (manual proto generation may be needed)
   - Rust CLI: `cd cli && cargo build` (auto-generated, strips Elixir options)
   - MCP: `cd mcp && cargo build` (auto-generated, strips Elixir options)

## Adding New Proto Files

When adding new `.proto` files:
1. Add them to `proto/` directory
2. Update `cli/build.rs` and `mcp/build.rs` to include them
3. Regenerate code for all platforms

