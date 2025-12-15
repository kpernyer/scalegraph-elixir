# Project Architecture

## System Overview

Scalegraph is a distributed ledger designed for multi-party ecosystems. It enables atomic financial transactions between participants in a business network.

```
┌─────────────────────────────────────────────────────────────┐
│                      Rust TUI CLI                           │
│                    (cli/src/main.rs)                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ gRPC (port 50051)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    gRPC Endpoint                            │
│               (Scalegraph.Endpoint)                         │
├─────────────────────────────────────────────────────────────┤
│   Ledger.Server          │         Participant.Server       │
│   - CreateAccount        │         - CreateParticipant      │
│   - GetAccount           │         - GetParticipant         │
│   - GetBalance           │         - ListParticipants       │
│   - Credit               │         - CreateAccount          │
│   - Debit                │         - GetAccounts            │
│   - Transfer             │                                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Core Layer                             │
├─────────────────────────────────────────────────────────────┤
│    Ledger.Core              │       Participant.Core        │
│    - Account operations     │       - Participant CRUD      │
│    - Transaction execution  │       - Account management    │
│    - Balance management     │       - Role validation       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Storage Layer (Mnesia)                    │
├─────────────────────────────────────────────────────────────┤
│  scalegraph_participants  │  scalegraph_accounts            │
│  - id (pk)                │  - id (pk)                      │
│  - name                   │  - participant_id (index)       │
│  - role                   │  - account_type                 │
│  - created_at             │  - balance                      │
│  - metadata               │  - created_at                   │
│                           │  - metadata                     │
├───────────────────────────┴─────────────────────────────────┤
│  scalegraph_transactions                                    │
│  - id (pk)                                                  │
│  - type                                                     │
│  - entries                                                  │
│  - timestamp                                                │
│  - reference                                                │
└─────────────────────────────────────────────────────────────┘
```

## Components

### Application Entry Point

**`Scalegraph.Application`** (`lib/scalegraph/application.ex`)
- OTP Application behaviour
- Initializes Mnesia schema on startup
- Starts gRPC server supervisor

### gRPC Layer

**`Scalegraph.Endpoint`** (`lib/scalegraph/application.ex`)
- Configures gRPC services and interceptors
- Routes to Ledger and Participant servers

**`Scalegraph.Ledger.Server`** (`lib/scalegraph/ledger/server.ex`)
- Implements LedgerService gRPC endpoints
- Translates between protobuf and internal formats
- Handles gRPC error mapping

**`Scalegraph.Participant.Server`** (`lib/scalegraph/participant/server.ex`)
- Implements ParticipantService gRPC endpoints
- Manages participant lifecycle via gRPC

### Core Layer

**`Scalegraph.Ledger.Core`** (`lib/scalegraph/ledger/core.ex`)
- Account CRUD operations
- Single-entry transactions (credit/debit)
- Multi-party atomic transfers
- Balance management with overdraft protection

**`Scalegraph.Participant.Core`** (`lib/scalegraph/participant/core.ex`)
- Participant registration and lookup
- Role-based participant types
- Participant account creation
- Account listing by participant

### Storage Layer

**`Scalegraph.Storage.Schema`** (`lib/scalegraph/storage/schema.ex`)
- Mnesia schema initialization
- Table definitions with disc persistence
- Secondary index on participant_id
- Utility functions for testing

### Protobuf

**`Scalegraph.Proto.Ledger`** (`lib/scalegraph/proto/ledger.pb.ex`)
- Generated protobuf message types
- Service definitions

### Utilities

**`Scalegraph.Seed`** (`lib/scalegraph/seed.ex`)
- Demo data seeding
- Creates example ecosystem participants

## Domain Model

### Participants

Participants represent organizations in the ecosystem. Each has a role:

| Role | Description | Example |
|------|-------------|---------|
| `access_provider` | Physical access control | ASSA ABLOY |
| `banking_partner` | Financial services | SEB |
| `ecosystem_partner` | Platform operators | Beauty Hosting |
| `supplier` | Product suppliers | Schampo etc |
| `equipment_provider` | Pay-per-use equipment | Hairgrowers United |

### Accounts

Accounts hold balances and are linked to participants:

| Type | Purpose |
|------|---------|
| `standalone` | Independent account |
| `operating` | Main business account |
| `receivables` | Incoming payments |
| `payables` | Outgoing payments |
| `escrow` | Held funds |
| `fees` | Fee collection |
| `usage` | Pay-per-use tracking |

### Transactions

All balance changes are recorded as transactions:
- Single-entry: credit or debit
- Multi-entry: atomic transfers between multiple accounts

## Data Flow

### Transfer Flow

```
1. Client sends Transfer request via gRPC
2. Ledger.Server receives request, extracts entries
3. Ledger.Core.transfer/2 starts Mnesia transaction
4. For each entry:
   a. Read account
   b. Validate sufficient balance
   c. Update balance
5. Record transaction entry
6. Commit transaction
7. Return result to client
```

### Participant Creation Flow

```
1. Client sends CreateParticipant request
2. Participant.Server validates role
3. Participant.Core.create_participant/4 starts transaction
4. Check for existing participant
5. Insert participant record
6. Return result
7. Client creates accounts for participant
```

## CLI Architecture

The Rust CLI provides a TUI interface:

```
cli/
├── src/
│   ├── main.rs        # Entry point, Tokio runtime
│   ├── grpc/
│   │   └── mod.rs     # gRPC client, proto types
│   └── ui/
│       ├── mod.rs     # UI module exports
│       ├── app.rs     # Application state
│       └── views.rs   # TUI views/widgets
└── proto/
    └── ledger.proto   # Service definitions
```

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `grpc_port` | 50051 | gRPC server port |

## Dependencies

### Elixir
- `grpc` - gRPC server
- `protobuf` - Protocol buffer support

### Rust CLI
- `tonic` - gRPC client
- `ratatui` - TUI framework
- `tokio` - Async runtime
- `clap` - CLI argument parsing
