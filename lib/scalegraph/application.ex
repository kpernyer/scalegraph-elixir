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
    case Scalegraph.Storage.Schema.init_with_migration() do
      :ok ->
        # Auto-seed with example data (ram_copies don't persist between restarts)
        Logger.info("Seeding database with example participants...")
        Scalegraph.Seed.run()
        continue_startup()

      {:error, :schema_migration_failed} ->
        Logger.error("Cannot start application: schema migration failed")
        {:error, :schema_migration_failed}

      error ->
        Logger.error("Failed to initialize schema: #{inspect(error)}")
        {:error, error}
    end
  end

  defp continue_startup do

    port = Application.get_env(:scalegraph, :grpc_port, 50051)

    # Check if port is already in use before attempting to start
    Logger.info("Checking if port #{port} is available...")
    case check_port_available(port) do
      {:ok, :available} ->
        Logger.info("Port #{port} is available, proceeding with server startup")
        # Port is available, proceed with starting the server
        children = [
          {GRPC.Server.Supervisor, endpoint: Scalegraph.Endpoint, port: port, start_server: true}
        ]

        opts = [strategy: :one_for_one, name: Scalegraph.Supervisor]

        Logger.info("Starting gRPC server on port #{port}")

        case Supervisor.start_link(children, opts) do
          {:ok, _pid} = result ->
            Logger.info("✅ Scalegraph server started successfully on port #{port}")
            result

          {:error, {:shutdown, {:failed_to_start_child, _, {:listen_error, _, :eaddrinuse}}}} ->
            # Fallback error handling if port check didn't catch it
            Logger.error("""
            ════════════════════════════════════════════════════════════════════════
            Failed to start: Port #{port} is already in use
            ════════════════════════════════════════════════════════════════════════

            Another process is using port #{port}. To fix:

            1. Check what's using the port:
               lsof -i :#{port}

            2. Kill the process (replace PID with actual process ID):
               kill <PID>

            3. Or kill all processes on the port:
               lsof -ti :#{port} | xargs kill

            4. Then start the server again:
               mix run --no-halt

            ════════════════════════════════════════════════════════════════════════
            """)

            {:error, {:shutdown, "Port #{port} is already in use"}}

          {:error, reason} ->
            Logger.error("Failed to start server: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, {:in_use, pid, process_name}} ->
        Logger.error("""
        ════════════════════════════════════════════════════════════════════════
        Port #{port} is already in use!
        ════════════════════════════════════════════════════════════════════════

        Process: #{process_name} (PID: #{pid})

        The Scalegraph server is already running. To fix this:

        1. If you want to use the existing server, just connect to it.

        2. If you want to restart the server:
           - Find and kill the process: kill #{pid}
           - Or use: lsof -ti :#{port} | xargs kill
           - Then start the server again

        3. To check what's using the port:
           lsof -i :#{port}

        ════════════════════════════════════════════════════════════════════════
        """)

        {:error,
         {:shutdown, "Port #{port} is already in use by process #{pid} (#{process_name})"}}

      {:error, reason} ->
        Logger.error("Failed to check port #{port}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Check if a port is available
  defp check_port_available(port) do
    case :inet.getaddr(~c"localhost", :inet) do
      {:ok, _ip} ->
        case :gen_tcp.listen(port, [:binary, {:active, false}]) do
          {:ok, socket} ->
            :gen_tcp.close(socket)
            {:ok, :available}

          {:error, :eaddrinuse} ->
            # Port is in use, try to find the process
            case find_port_process(port) do
              {:ok, {pid, name}} ->
                {:error, {:in_use, pid, name}}

              {:error, _} ->
                {:error, {:in_use, :unknown, "unknown process"}}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Try to find the process using the port (Unix/Linux/macOS)
  defp find_port_process(port) do
    case System.cmd("lsof", ["-ti", ":#{port}"], stderr_to_stdout: true) do
      {pid_str, 0} ->
        pid_str = String.trim(pid_str)

        if pid_str != "" do
          pid = String.to_integer(pid_str)

          # Try to get process name
          case System.cmd("ps", ["-p", pid_str, "-o", "comm="], stderr_to_stdout: true) do
            {name, 0} ->
              name = String.trim(name)
              {:ok, {pid, if(name == "", do: "unknown", else: name)}}

            _ ->
              {:ok, {pid, "unknown"}}
          end
        else
          {:error, :not_found}
        end

      _ ->
        {:error, :lsof_not_available}
    end
  rescue
    _ -> {:error, :check_failed}
  end
end

defmodule Scalegraph.Endpoint do
  @moduledoc """
  gRPC Endpoint configuration.
  """

  use GRPC.Endpoint

  intercept(GRPC.Server.Interceptors.Logger)

  run(Scalegraph.Ledger.Server)
  run(Scalegraph.Participant.Server)
  run(Scalegraph.Business.Server)
end
