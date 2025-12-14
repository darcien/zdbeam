defmodule Mix.Tasks.Zdbeam.TestLog do
  @moduledoc """
  Simulates parsing a Zwift log file to debug activity detection.

  ## Usage

      mix zdbeam.test_log <path>
      mix zdbeam.test_log ~/Documents/Zwift/Logs/Log.txt
      mix zdbeam.test_log logs.txt --chunk-size 1000

  ## Options

    * `--chunk-size <n>` - Number of lines per check (default: 600)

  """

  use Mix.Task

  @shortdoc "Test log file parsing for debugging"

  @impl Mix.Task
  def run(args) do
    {opts, paths, _} =
      OptionParser.parse(args,
        switches: [
          chunk_size: :integer
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
          chunk_size: opts[:chunk_size] || 600
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
