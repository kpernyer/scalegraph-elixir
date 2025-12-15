defmodule Mix.Tasks.Scalegraph.Seed do
  @moduledoc """
  Seeds the Scalegraph database with example participants.

  ## Usage

      mix scalegraph.seed

  ## Options

      --reset  Clear existing data before seeding

  ## Note

  This task must be run when the server is NOT running,
  or use `Scalegraph.Seed.run()` in IEx when connected to a running server.
  """

  use Mix.Task

  @shortdoc "Seed the Scalegraph database with example participants"

  @impl Mix.Task
  def run(args) do
    # Start the application (which starts Mnesia)
    Mix.Task.run("app.start")

    reset? = "--reset" in args

    if reset? do
      Mix.shell().info("Resetting database...")
      result = Scalegraph.Seed.reset()
      Mix.shell().info("Reset complete: #{inspect(result)}")
    else
      Mix.shell().info("Seeding database...")
      result = Scalegraph.Seed.run()
      Mix.shell().info("Seed complete: #{inspect(result)}")
    end
  end
end
