# Scalegraph Ledger - Justfile
# https://github.com/casey/just

# Default recipe - show available commands
default:
    @just --list

# ============================================================================
# ENVIRONMENT SETUP (First Time)
# ============================================================================

# Install Elixir, Erlang, Rust and all tools (macOS)
install-env-macos:
    @echo "🍺 Installing Elixir/Erlang via Homebrew..."
    brew install elixir erlang protobuf rust just
    @echo ""
    @echo "✅ Environment installed!"
    @echo "   Restart your terminal, then run: just setup"


# Check if required tools are installed
check-env:
    @echo "Checking environment..."
    @echo -n "  Erlang:  " && (erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null || echo "❌ NOT INSTALLED")
    @echo -n "  Elixir:  " && (elixir --version 2>/dev/null | head -1 || echo "❌ NOT INSTALLED")
    @echo -n "  Mix:     " && (mix --version 2>/dev/null || echo "❌ NOT INSTALLED")
    @echo -n "  Rust:    " && (rustc --version 2>/dev/null || echo "❌ NOT INSTALLED")
    @echo -n "  Cargo:   " && (cargo --version 2>/dev/null || echo "❌ NOT INSTALLED")
    @echo -n "  Protoc:  " && (protoc --version 2>/dev/null || echo "❌ NOT INSTALLED")
    @echo ""
    @echo "If anything is missing, run:"
    @echo "  macOS:  just install-env-macos"
    @echo "  Debian: just install-env-debian"
    @echo "  asdf:   just install-env-asdf"

# ============================================================================
# SETUP (After Environment is Installed)
# ============================================================================

# Install all dependencies (Elixir + Rust)
setup: setup-elixir setup-rust
    @echo "✅ All dependencies installed"

# Install Elixir dependencies
setup-elixir:
    @echo "📦 Installing Elixir dependencies..."
    mix deps.get

# Install Rust dependencies (builds CLI)
setup-rust:
    @echo "📦 Installing Rust dependencies..."
    cd cli && cargo fetch

# Initialize the database and seed data (server must NOT be running)
init: setup-elixir
    @echo "🗄️  Initializing database and seeding data..."
    @echo "⚠️  Make sure the server is NOT running!"
    mix scalegraph.seed
    @echo "✅ Database initialized with sample participants"

# Clean and reinitialize everything (server must NOT be running)
reset:
    @echo "🧹 Resetting database..."
    @echo "⚠️  Make sure the server is NOT running!"
    mix scalegraph.seed --reset
    @echo "✅ Database reset complete"

# Reset system to initial known state (PREDICTABLE)
# This target:
#   1. Keeps the schema intact
#   2. Clears ALL data from all tables
#   3. Reloads data from priv/seed_data.yaml
# Server must NOT be running for this to work correctly.
reset-system-to-initial-known-state:
    @echo "═══════════════════════════════════════════════════════════════"
    @echo "  RESET SYSTEM TO INITIAL KNOWN STATE"
    @echo "═══════════════════════════════════════════════════════════════"
    @echo ""
    @echo "⚠️  CRITICAL: The server MUST NOT be running!"
    @echo "   If the server is running, stop it first (Ctrl+C or kill process)"
    @echo ""
    @echo "This will:"
    @echo "  ✓ Keep the database schema intact"
    @echo "  ✓ Clear ALL data from all tables (participants, accounts, transactions)"
    @echo "  ✓ Reload all data from priv/seed_data.yaml"
    @echo ""
    @echo "Starting reset process..."
    @echo ""
    mix scalegraph.seed --reset
    @echo ""
    @echo "═══════════════════════════════════════════════════════════════"
    @echo "  ✅ System reset to initial known state complete"
    @echo "═══════════════════════════════════════════════════════════════"
    @echo ""
    @echo "The database now contains only the data from priv/seed_data.yaml"
    @echo "You can now start the server with: just run"

# Seed via running server (use when server IS running)
seed-live:
    @echo "🗄️  Seeding via running server..."
    @echo "Run this in IEx: Scalegraph.Seed.run()"
    @echo "Or start with: iex -S mix"

# ============================================================================
# BUILD
# ============================================================================

# Build everything
build: build-elixir build-cli
    @echo "✅ All builds complete"

# Compile Elixir project
build-elixir:
    @echo "🔨 Compiling Elixir project..."
    mix compile

# Build Rust CLI (debug)
build-cli:
    @echo "🔨 Building Rust CLI (debug)..."
    cd cli && cargo build

# Build Rust CLI (release)
build-cli-release:
    @echo "🔨 Building Rust CLI (release)..."
    cd cli && cargo build --release

# Build release for all platforms
build-release: build-elixir build-cli-release
    @echo "✅ Release builds complete"

# ============================================================================
# RUN
# ============================================================================

# Start the Elixir gRPC server
run:
    @echo "🚀 Starting Scalegraph server on port 50051..."
    mix run --no-halt

# Start server in interactive mode (IEx)
run-iex:
    @echo "🚀 Starting Scalegraph server (interactive)..."
    iex -S mix

# Run the CLI (debug build)
cli *ARGS:
    @echo "🖥️  Launching Scalegraph CLI..."
    cd cli && cargo run -- {{ARGS}}

# Run the CLI (release build)
cli-release *ARGS:
    ./cli/target/release/scalegraph {{ARGS}}

# Start server and CLI in split terminal (requires tmux)
run-all:
    @echo "🚀 Starting server and CLI..."
    tmux new-session -d -s scalegraph 'just run' \; \
         split-window -h 'sleep 2 && just cli' \; \
         attach

# ============================================================================
# TEST
# ============================================================================

# Run all tests
test: test-elixir test-cli
    @echo "✅ All tests passed"

# Run Elixir tests
test-elixir:
    @echo "🧪 Running Elixir tests..."
    mix test

# Run Elixir tests with coverage
test-elixir-cover:
    @echo "🧪 Running Elixir tests with coverage..."
    mix test --cover

# Run Rust CLI tests
test-cli:
    @echo "🧪 Running Rust CLI tests..."
    cd cli && cargo test

# Run tests in watch mode (requires mix_test_watch)
test-watch:
    mix test.watch

# ============================================================================
# LINT & FORMAT
# ============================================================================

# Format all code
fmt: fmt-elixir fmt-rust
    @echo "✅ All code formatted"

# Format Elixir code
fmt-elixir:
    @echo "🎨 Formatting Elixir code..."
    mix format

# Format Rust code
fmt-rust:
    @echo "🎨 Formatting Rust code..."
    cd cli && cargo fmt

# Check formatting without changes
fmt-check: fmt-check-elixir fmt-check-rust

fmt-check-elixir:
    mix format --check-formatted

fmt-check-rust:
    cd cli && cargo fmt --check

# Lint Elixir code (requires credo)
lint-elixir:
    @echo "🔍 Linting Elixir code..."
    mix credo --strict || true

# Lint Rust code
lint-rust:
    @echo "🔍 Linting Rust code..."
    cd cli && cargo clippy -- -D warnings

# Lint all code
lint: lint-elixir lint-rust


# ============================================================================
# DEPLOY
# ============================================================================

# Build a release for deployment
release:
    @echo "📦 Building Elixir release..."
    MIX_ENV=prod mix release
    @echo "✅ Release built at _build/prod/rel/scalegraph"

# Build release with CLI bundled
release-full: release build-cli-release
    @echo "📦 Copying CLI to release..."
    mkdir -p _build/prod/rel/scalegraph/bin
    cp cli/target/release/scalegraph _build/prod/rel/scalegraph/bin/scalegraph-cli
    @echo "✅ Full release ready at _build/prod/rel/scalegraph"

# Build Docker image
docker-build:
    @echo "🐳 Building Docker image..."
    docker build -t scalegraph:latest .
    @echo "✅ Docker image built: scalegraph:latest"

# Run in Docker
docker-run:
    @echo "🐳 Running Scalegraph in Docker..."
    docker run -p 50051:50051 scalegraph:latest

# Push to container registry
docker-push REGISTRY:
    @echo "🐳 Pushing to {{REGISTRY}}..."
    docker tag scalegraph:latest {{REGISTRY}}/scalegraph:latest
    docker push {{REGISTRY}}/scalegraph:latest

# Deploy to production (customize as needed)
deploy ENV="staging":
    @echo "🚀 Deploying to {{ENV}}..."
    @echo "⚠️  Customize this recipe for your deployment target"
    # Example: kubectl apply -f k8s/{{ENV}}/
    # Example: fly deploy --config fly.{{ENV}}.toml
    # Example: ssh {{ENV}}-server 'cd /app && git pull && just release && just restart'

# ============================================================================
# DEVELOPMENT
# ============================================================================

# Start development environment
dev: setup
    @echo "🛠️  Development environment ready"
    @echo "   Run 'just run' to start the server"
    @echo "   Run 'just cli' to start the CLI"

# Watch for changes and recompile (requires file watcher)
watch:
    @echo "👀 Watching for changes..."
    mix compile --force && fswatch -o lib | xargs -n1 -I{} mix compile

# Generate documentation
docs:
    @echo "📚 Generating documentation..."
    mix docs
    @echo "✅ Documentation available at doc/index.html"

# Open IEx with project loaded
console:
    iex -S mix

# ============================================================================
# PROTO
# ============================================================================

# Regenerate protobuf files (if using protoc directly)
proto:
    @echo "📝 Regenerating protobuf files..."
    @echo "   Source: proto/ledger.proto (single source of truth)"
    @echo "   Elixir: Manual generation required (see lib/scalegraph/proto/)"
    @echo "   Rust: Auto-generated on cargo build via build.rs"
    cd cli && cargo build

# ============================================================================
# CLEAN
# ============================================================================

# Clean all build artifacts
clean: clean-elixir clean-rust
    @echo "✅ All clean"

# Clean Elixir build artifacts
clean-elixir:
    @echo "🧹 Cleaning Elixir artifacts..."
    mix clean
    rm -rf _build deps

# Clean Rust build artifacts
clean-rust:
    @echo "🧹 Cleaning Rust artifacts..."
    cd cli && cargo clean

# Clean Mnesia data
clean-db:
    @echo "🧹 Cleaning Mnesia data..."
    rm -rf Mnesia.*

# Deep clean everything
clean-all: clean clean-db
    @echo "✅ Deep clean complete"

# ============================================================================
# HELP
# ============================================================================

# Show quick start guide
help:
    @echo ""
    @echo "╔═══════════════════════════════════════════════════════════════╗"
    @echo "║             SCALEGRAPH LEDGER - QUICK START                   ║"
    @echo "╠═══════════════════════════════════════════════════════════════╣"
    @echo "║                                                               ║"
    @echo "║  FIRST TIME (install Elixir/Rust):                            ║"
    @echo "║    just check-env              (check what's installed)       ║"
    @echo "║    just install-env-macos      (macOS via Homebrew)           ║"
    @echo "║                                                               ║"
    @echo "║  AFTER ENVIRONMENT IS READY:                                  ║"
    @echo "║    1. just setup               (install dependencies)         ║"
    @echo "║    2. just init                (seed database)                ║"
    @echo "║    3. just run                 (start server)                 ║"
    @echo "║    4. just cli                 (start CLI - new terminal)     ║"
    @echo "║                                                               ║"
    @echo "║  OTHER COMMANDS:                                              ║"
    @echo "║    just test                   (run all tests)                ║"
    @echo "║    just install                (install CLI globally)         ║"
    @echo "║    just --list                 (show all commands)            ║"
    @echo "║                                                               ║"
    @echo "╚═══════════════════════════════════════════════════════════════╝"
    @echo ""

# Show system info
info:
    @echo "System Information:"
    @echo "  Elixir: $(elixir --version | head -1)"
    @echo "  Rust:   $(rustc --version)"
    @echo "  Cargo:  $(cargo --version)"
    @echo "  Just:   $(just --version)"
