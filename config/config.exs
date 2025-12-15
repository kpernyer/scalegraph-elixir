import Config

# Note: start_server is now passed directly to GRPC.Server.Supervisor
# See lib/scalegraph/application.ex

config :scalegraph,
  grpc_port: 50051
