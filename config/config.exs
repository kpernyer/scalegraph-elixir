import Config

# Note: start_server is now passed directly to GRPC.Server.Supervisor
# See lib/scalegraph/application.ex

config :scalegraph,
  grpc_port: 50051,
  # Mnesia storage type: :disc_copies (persistent) or :ram_copies (in-memory)
  # Default to disc_copies for data persistence
  mnesia_storage: :disc_copies

# Mnesia directory for disc_copies
config :mnesia, dir: ~c"./priv/mnesia_data"
