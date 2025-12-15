defmodule Scalegraph.MixProject do
  use Mix.Project

  def project do
    [
      app: :scalegraph,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :mnesia],
      mod: {Scalegraph.Application, []}
    ]
  end

  defp deps do
    [
      {:grpc, "~> 0.7"},
      {:protobuf, "~> 0.12"},
      {:yaml_elixir, "~> 2.9"}
    ]
  end
end
