defmodule Zdbeam.Application do
  @moduledoc """
  Main application supervisor for Zdbeam.

  Starts and supervises the core processes:
  - ZwiftReader: Monitors Zwift activity
  - DiscordRPC: Handles Discord Rich Presence updates
  """

  use Application
  require Logger

  @app_name "zdbeam"

  @impl true
  def start(_type, _args) do
    # In test mode, start with minimal supervision tree
    if Application.get_env(:zdbeam, :start_genservers, true) do
      args = Burrito.Util.Args.argv()

      case parse_and_configure(args) do
        :ok ->
          Logger.info("starting application")

          children = [
            {Zdbeam.ZwiftReader, []},
            {Zdbeam.DiscordRPC, []}
          ]

          opts = [strategy: :one_for_one, name: Zdbeam.Supervisor]
          Supervisor.start_link(children, opts)

        :help ->
          print_help()
          System.halt(0)

        :version ->
          print_version()
          System.halt(0)

        {:error, message} ->
          IO.puts(:stderr, message)
          System.halt(1)
      end
    else
      # Test mode: empty supervisor tree
      Supervisor.start_link([], strategy: :one_for_one, name: Zdbeam.Supervisor)
    end
  end

  defp parse_and_configure(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          help: :boolean,
          version: :boolean,
          app_id: :string,
          check_interval: :integer,
          log_level: :string,
          test_mode: :boolean,
          test_log: :string
        ],
        aliases: [
          h: :help,
          v: :version,
          a: :app_id,
          i: :check_interval,
          l: :log_level,
          t: :test_mode
        ]
      )

    cond do
      opts[:help] ->
        :help

      opts[:version] ->
        :version

      opts[:test_log] ->
        run_log_simulation(opts[:test_log])

      true ->
        configure_app(opts)
    end
  end

  @spec run_log_simulation(String.t()) :: no_return()
  defp run_log_simulation(log_path) do
    case Zdbeam.LogSimulator.simulate_file(log_path) do
      :ok ->
        System.halt(0)

      {:error, _reason} ->
        System.halt(1)
    end
  end

  defp configure_app(opts) do
    app_id = opts[:app_id]

    if is_nil(app_id) do
      {:error, "#{@app_name}: --app-id required"}
    else
      do_configure_app(app_id, opts)
    end
  end

  defp do_configure_app(app_id, opts) do
    Application.put_env(:zdbeam, :discord_application_id, app_id)

    if opts[:check_interval] do
      Application.put_env(:zdbeam, :check_interval, :timer.seconds(opts[:check_interval]))
    end

    # TODO: remove test mode or replace with static mode
    # Having a static activity to test the presence itself is useful,
    # doing race or RoboPacer while holding a keyboard is not easy.
    test_mode = opts[:test_mode] || false
    Application.put_env(:zdbeam, :test_mode, test_mode)

    log_level =
      case opts[:log_level] do
        level when level in ["debug", "info", "warning", "error"] ->
          String.to_existing_atom(level)

        nil ->
          :info

        invalid ->
          IO.puts(:stderr, "warning: invalid log level '#{invalid}', using 'info'")
          :info
      end

    Logger.configure(level: log_level)

    check_interval_ms = Application.get_env(:zdbeam, :check_interval)
    check_interval_s = div(check_interval_ms, 1000)
    print_banner(app_id, check_interval_s, log_level, test_mode)

    :ok
  end

  defp print_banner(app_id, check_interval, log_level, test_mode) do
    test_mode_str = if test_mode, do: " (test mode)", else: ""

    IO.puts("""
    starting#{test_mode_str}
    app_id: #{app_id}
    check_interval: #{check_interval}s
    log_level: #{log_level}
    """)

    :ok
  end

  defp print_help do
    IO.puts("""
    usage: #{@app_name} --app-id <id> [options]

    Discord Rich Presence integration for Zwift

    options:
      -a, --app-id <id>           Discord Application ID (required)
      -i, --check-interval <sec>  Check interval in seconds (default: 5)
      -l, --log-level <level>     Log level: debug|info|warning|error (default: info)
      -t, --test-mode             Test mode with hardcoded activity
      --test-log <path>           Simulate parsing a log file for debugging
      -h, --help                  Show this help
      -v, --version               Show version

    See https://discord.com/developers/applications for application ID.
    """)
  end

  defp print_version do
    IO.puts("#{@app_name} #{Application.spec(:zdbeam, :vsn)}")
  end
end
