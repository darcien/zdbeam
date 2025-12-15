defmodule Mix.Tasks.Zdbeam.TestLog do
  @moduledoc """
  Simulates parsing a Zwift log file to debug activity detection.

  ## Usage

      mix zdbeam.test_log <path>
      mix zdbeam.test_log ~/Documents/Zwift/Logs/Log.txt
      mix zdbeam.test_log logs.txt --check-interval 10
      mix zdbeam.test_log logs.txt -i 10

  ## Options

    * `-i, --check-interval <n>` - Seconds between checks (default: 5)

  """

  use Mix.Task

  @shortdoc "Test log file parsing for debugging"
  @default_check_interval 5

  @impl Mix.Task
  def run(args) do
    {opts, paths, _} =
      OptionParser.parse(args,
        switches: [
          check_interval: :integer
        ],
        aliases: [
          i: :check_interval
        ]
      )

    case paths do
      [] ->
        Mix.shell().error("log file path required")
        Mix.shell().info("usage: mix zdbeam.test_log <path>")
        Mix.shell().info("example: mix zdbeam.test_log ~/Documents/Zwift/Logs/Log.txt")
        exit({:shutdown, 1})

      [path | _] ->
        simulation_opts = [
          check_interval: opts[:check_interval] || @default_check_interval
        ]

        case Zdbeam.LogSimulator.simulate_file(path, simulation_opts) do
          :ok ->
            :ok

          {:error, _reason} ->
            exit({:shutdown, 1})
        end
    end
  end
end
