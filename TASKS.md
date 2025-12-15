# Scalegraph Ledger - Tasks

## Pending

### Participant Service Declarations
- **Priority:** High
- **Location:** Multiple files
- **Details:**
  - Add `services` field to Participant table (list of service identifiers)
  - Update proto file to include services in Participant message
  - Add Core functions: `add_service/2`, `remove_service/2`, `list_services/1`
  - Add gRPC endpoints: `AddService`, `RemoveService`, `ListServices`
  - Update participant record format and conversion functions

### Switch Mnesia to persistent storage (disc_copies)
- **Priority:** After initial testing complete
- **Status:** ✅ COMPLETED (Steps 1-3 done)
- **Location:** `lib/scalegraph/storage/schema.ex`
- **Remaining:**
  - Remove auto-seed from `application.ex` (data will persist)
  - Update `Justfile` with `init` task for first-time seeding

## Completed

- [x] Basic ledger with gRPC/protobuf API
- [x] Participant concept with ecosystem entities
- [x] Rust TUI CLI with Ratatui
- [x] Auto-seed on startup (ram_copies mode)
- [x] CLI `--check` flag for health verification
