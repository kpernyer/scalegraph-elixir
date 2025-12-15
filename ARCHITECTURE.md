# Architecture

## High-Level Design

Scalegraph follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────┐
│                 Transport Layer                 │
│                   (gRPC)                        │
├─────────────────────────────────────────────────┤
│                 Service Layer                   │
│          (Ledger.Server, Participant.Server)    │
├─────────────────────────────────────────────────┤
│                  Core Layer                     │
│           (Ledger.Core, Participant.Core)       │
├─────────────────────────────────────────────────┤
│                 Storage Layer                   │
│                   (Mnesia)                      │
└─────────────────────────────────────────────────┘
```

## Layer Responsibilities

### Transport Layer

The gRPC endpoint handles:
- Protocol buffer serialization/deserialization
- Request routing to services
- Logging via interceptor

### Service Layer

Server modules handle:
- Request validation
- Error mapping to gRPC status codes
- Proto-to-internal type conversion

### Core Layer

Business logic modules handle:
- Domain operations
- Transaction management
- Invariant enforcement (e.g., no negative balances)

### Storage Layer

Mnesia handles:
- Data persistence to disk
- ACID transactions
- Secondary indexing

## Transaction Model

### Atomicity

All ledger operations use Mnesia transactions:

```elixir
:mnesia.transaction(fn ->
  # 1. Read all involved accounts
  # 2. Validate constraints
  # 3. Update balances
  # 4. Record transaction
end)
```

If any step fails, the entire transaction aborts.

### Multi-Party Transfers

Transfers support arbitrary numbers of parties:

```elixir
Ledger.transfer([
  {"account_a", -100},  # debit
  {"account_b", 80},    # credit
  {"fee_account", 20}   # fee
], "reference")
```

The sum doesn't need to be zero, allowing for fees, taxes, etc.

## OTP Application Structure

```
Scalegraph.Application
└── Supervisor (one_for_one)
    └── GRPC.Server.Supervisor
        └── gRPC Server (port 50051)
```

The application:
1. Initializes Mnesia schema before supervision tree starts
2. Starts gRPC server under supervision

## Database Schema

### Tables

| Table | Key | Indices | Storage |
|-------|-----|---------|---------|
| `scalegraph_participants` | id | - | disc_copies |
| `scalegraph_accounts` | id | participant_id | disc_copies |
| `scalegraph_transactions` | id | - | disc_copies |

### Record Formats

**Participants:**
```
{:scalegraph_participants, id, name, role, created_at, metadata}
```

**Accounts:**
```
{:scalegraph_accounts, id, participant_id, account_type, balance, created_at, metadata}
```

**Transactions:**
```
{:scalegraph_transactions, id, type, entries, timestamp, reference}
```

## Error Handling

### Core Layer

Returns tagged tuples:
- `{:ok, result}` on success
- `{:error, reason}` on failure

Common error reasons:
- `:not_found` - Resource doesn't exist
- `:account_exists` - Account already exists
- `:participant_exists` - Participant already exists
- `{:insufficient_funds, message}` - Balance too low
- `{:invalid_role, role, valid_roles}` - Invalid participant role

### Service Layer

Maps errors to gRPC status codes:

| Error | gRPC Status |
|-------|-------------|
| `:not_found` | `NOT_FOUND` |
| `:account_exists` | `ALREADY_EXISTS` |
| `{:insufficient_funds, _}` | `FAILED_PRECONDITION` |
| Other | `INTERNAL` |

## Concurrency Model

### Mnesia Transactions

Mnesia uses pessimistic locking:
- Read locks for reads
- Write locks for writes
- Automatic deadlock detection and resolution

### gRPC Server

The gRPC server handles requests concurrently. Each request runs in its own process, with Mnesia managing isolation.

## Scalability Considerations

### Current Design

Single-node deployment with:
- Mnesia disc_copies for durability
- All data in memory for fast access

### Future Scaling Options

1. **Multi-node Mnesia cluster**: Replicate data across nodes
2. **Read replicas**: Add ram_copies nodes for read scaling
3. **Sharding**: Partition accounts by participant

## Security Model

### Current State

- No authentication on gRPC
- No TLS configured
- Single-tenant deployment assumed

### Production Recommendations

1. Enable gRPC TLS
2. Add authentication interceptor
3. Implement authorization checks
4. Audit logging for all operations

## Monitoring Points

Key metrics to track:
- Transaction throughput
- Transaction latency
- Mnesia table sizes
- gRPC error rates by status code

## Deployment

### Development

```bash
iex -S mix
```

### Production

```bash
MIX_ENV=prod mix release
_build/prod/rel/scalegraph/bin/scalegraph start
```

Mnesia data stored in `Mnesia.nonode@nohost/` (or node-specific directory).
