# Scalegraph Ledger - Tasks

## Pending

### Switch Mnesia to persistent storage (disc_copies)
- **Priority:** After initial testing complete
- **Location:** `lib/scalegraph/storage/schema.ex`
- **Details:**
  - Change `ram_copies: [node()]` to `disc_copies: [node()]` for all three tables
  - Configure Mnesia directory to `/home/kpernyer/db` to avoid node conflicts
  - Add to `config/config.exs`:
    ```elixir
    config :mnesia, dir: ~c"/home/kpernyer/db"
    ```
  - Update `init/0` to create schema on disk:
    ```elixir
    :mnesia.create_schema([node()])
    ```
  - Remove auto-seed from `application.ex` (data will persist)
  - Update `Justfile` with `init` task for first-time seeding

## Completed

- [x] Basic ledger with gRPC/protobuf API
- [x] Participant concept with ecosystem entities
- [x] Rust TUI CLI with Ratatui
- [x] Auto-seed on startup (ram_copies mode)
- [x] CLI `--check` flag for health verification
