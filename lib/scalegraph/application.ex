defmodule Scalegraph.Application do
  @moduledoc """
  Scalegraph OTP Application.

  Starts the Mnesia storage and gRPC server.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    # Initialize Mnesia schema before starting supervision tree
    Logger.info("Initializing Scalegraph Ledger...")
    :ok = Scalegraph.Storage.Schema.init()

    # Auto-seed with example data (ram_copies don't persist between restarts)
    Logger.info("Seeding database with example participants...")
    Scalegraph.Seed.run()

    port = Application.get_env(:scalegraph, :grpc_port, 50051)

    children = [
      {GRPC.Server.Supervisor, endpoint: Scalegraph.Endpoint, port: port, start_server: true}
    ]

    opts = [strategy: :one_for_one, name: Scalegraph.Supervisor]

    Logger.info("Starting gRPC server on port #{port}")
    Supervisor.start_link(children, opts)
  end
end

defmodule Scalegraph.Endpoint do
  @moduledoc """
  gRPC Endpoint configuration.
  """

  use GRPC.Endpoint

  intercept GRPC.Server.Interceptors.Logger

  run Scalegraph.Ledger.Server
  run Scalegraph.Participant.Server
  run Scalegraph.Business.Server
end
