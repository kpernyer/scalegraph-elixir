# Scalegraph MCP Server

MCP (Model Context Protocol) server for Scalegraph Ledger. Enables Claude Desktop to interact with the ledger API via gRPC.

## Build

```bash
cd mcp
cargo build --release
```

## Usage

### 1. Start the Elixir gRPC Server

```bash
cd ..  # scalegraph-elexir root
mix run --no-halt
```

The gRPC server starts on port 50051.

### 2. Configure Claude Desktop

Add to your Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS):

```json
{
  "mcpServers": {
    "scalegraph": {
      "command": "/path/to/scalegraph-elexir/mcp/target/release/scalegraph-mcp",
      "env": {
        "SCALEGRAPH_GRPC_URL": "http://localhost:50051"
      }
    }
  }
}
```

### 3. Restart Claude Desktop

Restart Claude Desktop to load the MCP server.

## Available Tools

| Tool | Description |
|------|-------------|
| `list_participants` | List all participants in the ecosystem |
| `create_participant` | Add a new participant (supplier, access provider, etc.) |
| `create_participant_account` | Create a ledger account for a participant |
| `get_participant_accounts` | Get all accounts for a participant |
| `get_account_balance` | Get balance for a specific account |
| `transfer` | Execute atomic multi-party transfer |
| `purchase_invoice` | Create B2B invoice (adds to receivables/payables) |
| `pay_invoice` | Settle a B2B invoice (transfers money + clears A/R, A/P) |
| `access_payment` | Real-time micro-payment for access control |

## Example Conversations

### Add a new participant
> "Create a new supplier called 'acme_hair' with name 'Acme Hair Products AB'"
> "Create operating and receivables accounts for acme_hair with $10,000 initial balance"

### List participants
> "Show me all participants in the Scalegraph system"

### Check account balances
> "What are the account balances for salon_glamour?"

### B2B Purchase Flow
> "Create a purchase invoice from schampo_etc to salon_glamour for $4,550.00 worth of shampoo"
> "Now pay that invoice"

### Access Payment
> "Process an access payment of $8.00 from salon_glamour to assa_abloy for door access, with a $0.50 platform fee going to beauty_hosting"

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SCALEGRAPH_GRPC_URL` | `http://localhost:50051` | gRPC server URL |
| `SCALEGRAPH_DEBUG` | (unset) | Enable debug output to stderr |

## Testing the MCP Server

You can test the server manually via stdin/stdout:

```bash
# Start the server
./target/release/scalegraph-mcp

# Send JSON-RPC request (paste and press Enter)
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}

# List tools
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}

# Call a tool
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_participants","arguments":{}}}
```
