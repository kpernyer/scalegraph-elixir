defmodule Scalegraph.GRPC.DebugLoggerInterceptor do
  @moduledoc """
  Custom gRPC interceptor that logs at DEBUG level for system operations.
  
  This replaces the default GRPC.Server.Interceptors.Logger to use DEBUG
  level for system logs (request handling, response times) while allowing
  business logic to log at INFO level with context.
  """

  require Logger

  @behaviour GRPC.Server.Interceptor

  @impl true
  def init(opts) do
    opts
  end

  @impl true
  def call(req, stream, next, _opts) do
    if Logger.compare_levels(:debug, Logger.level()) != :lt do
      Logger.metadata(request_id: Logger.metadata()[:request_id] || stream.request_id)

      Logger.debug("Handled by #{inspect(stream.server)}.#{elem(stream.rpc, 0)}")

      start = System.monotonic_time()
      result = next.(req, stream)
      stop = System.monotonic_time()

      status = elem(result, 0)
      diff = System.convert_time_unit(stop - start, :native, :microsecond)

      Logger.debug("Response #{inspect(status)} in #{formatted_diff(diff)}")

      result
    else
      next.(req, stream)
    end
  end

  defp formatted_diff(diff) when diff > 1000, do: [diff |> div(1000) |> Integer.to_string(), "ms"]
  defp formatted_diff(diff), do: [Integer.to_string(diff), "µs"]
end

