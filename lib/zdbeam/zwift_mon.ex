defmodule Zdbeam.ZwiftMon do
  @moduledoc """
  Monitors Zwift activity and reports it to Discord RPC.

  Polls Zwift log file every N seconds (default: 5) to detect activity changes
  and updates Discord presence accordingly.

  ## Examples

      # Automatically started by supervisor
      {:ok, _pid} = Zdbeam.ZwiftMon.start_link([])

      # Check current status
      Zdbeam.ZwiftMon.get_status()
      #=> %{
      #     zwift_running: true,
      #     current_activity: %{type: :free_ride, world: "Watopia", ...},
      #     activity_start_time: 1234567890
      #   }

  """

  use GenServer
  require Logger

  alias Zdbeam.ActivityFormatter
  alias Zdbeam.ZwiftLogParser

  defmodule State do
    defstruct [
      :zwift_running,
      :current_activity,
      :last_check,
      :activity_start_time,
      :log_position
    ]
  end

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current Zwift activity status.

  ## Examples

      Zdbeam.ZwiftMon.get_status()
      #=> %{
      #     zwift_running: true,
      #     current_activity: %{type: :workout, workout_name: "FTP Test", ...},
      #     activity_start_time: 1234567890
      #   }

  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Zwift monitor started")

    state = %State{
      zwift_running: false,
      current_activity: nil,
      last_check: nil,
      activity_start_time: nil,
      log_position: 0
    }

    # Schedule first check
    schedule_check()

    {:ok, state}
  end

  @impl true
  def handle_info(:check_zwift, state) do
    new_state = check_zwift_activity(state)
    schedule_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      zwift_running: state.zwift_running,
      current_activity: state.current_activity,
      activity_start_time: state.activity_start_time
    }

    {:reply, status, state}
  end

  ## Private Functions

  defp check_zwift_activity(state) do
    was_running = state.zwift_running
    is_running = is_zwift_running?()

    case {was_running, is_running} do
      {false, true} ->
        handle_zwift_started(state)

      {true, true} ->
        handle_zwift_running(state)

      {true, false} ->
        handle_zwift_stopped(state)

      {false, false} ->
        %{state | last_check: DateTime.utc_now()}
    end
  end

  defp handle_zwift_started(state) do
    Logger.info("Zwift started")

    {activity, new_position} =
      detect_activity_from_log(state.log_position, state.current_activity)

    start_time = System.system_time(:second)
    update_discord_presence(activity, start_time)

    %{
      state
      | zwift_running: true,
        current_activity: activity,
        activity_start_time: start_time,
        last_check: DateTime.utc_now(),
        log_position: new_position
    }
  end

  defp handle_zwift_running(state) do
    {activity, new_position} =
      detect_activity_from_log(state.log_position, state.current_activity)

    new_start_time =
      case {activity, state.current_activity} do
        {nil, _} -> nil
        {_activity, nil} -> System.system_time(:second)
        {_activity, _existing} -> state.activity_start_time
      end

    if activity != state.current_activity do
      Logger.info("activity changed: #{ActivityFormatter.for_log(activity)}")
      Logger.debug("activity details: #{inspect(activity)}")
      update_discord_presence(activity, new_start_time)
    end

    %{
      state
      | current_activity: activity,
        activity_start_time: new_start_time,
        last_check: DateTime.utc_now(),
        log_position: new_position
    }
  end

  defp handle_zwift_stopped(state) do
    Logger.info("Zwift stopped")
    Zdbeam.DiscordRPC.clear_presence()

    %{
      state
      | zwift_running: false,
        current_activity: nil,
        activity_start_time: nil,
        last_check: DateTime.utc_now()
    }
  end

  defp is_zwift_running? do
    Application.get_env(:zdbeam, :test_mode, false) or detect_zwift_process()
  end

  defp detect_zwift_process do
    case Burrito.Util.get_current_os() do
      :darwin -> is_process_running_macos()
      :linux -> is_process_running_linux()
      :windows -> is_process_running_windows()
    end
  end

  defp is_process_running_macos do
    case System.cmd("pgrep", ["-i", "zwiftapp"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output) != ""
      _ -> false
    end
  end

  defp is_process_running_linux do
    case System.cmd("pgrep", ["-i", "zwiftapp"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output) != ""
      _ -> false
    end
  end

  defp is_process_running_windows do
    case System.cmd("tasklist", ["/FI", "IMAGENAME eq ZwiftApp.exe", "/NH"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> String.contains?(output, "ZwiftApp")
      _ -> false
    end
  end

  defp detect_activity_from_log(last_position, current_activity) do
    log_path = get_zwift_log_path()

    with true <- File.exists?(log_path),
         {:ok, content} <- File.read(log_path) do
      new_content = binary_part(content, last_position, byte_size(content) - last_position)

      activity =
        new_content
        |> String.split("\n")
        |> ZwiftLogParser.parse_log_lines(current_activity)

      {activity, byte_size(content)}
    else
      _ -> {nil, last_position}
    end
  end

  defp get_zwift_log_path do
    case Burrito.Util.get_current_os() do
      :darwin -> Path.expand("~/Documents/Zwift/Logs/Log.txt")
      _ -> Path.expand("~/Documents/Zwift/Logs/Log.txt")
    end
  end

  defp update_discord_presence(nil, start_time) do
    discord_activity = %{
      details: random_idle_message(),
      state: "Idling",
      start_time: start_time,
      large_image: "zwift_logo",
      large_text: random_idle_message(),
      small_image: nil,
      small_text: nil
    }

    Logger.debug("activity state (idle): activity=nil, start_time=#{start_time}")
    Logger.debug("updating Discord presence (idle): #{inspect(discord_activity)}")
    Zdbeam.DiscordRPC.update_presence(discord_activity)
  end

  defp update_discord_presence(activity, start_time) do
    {details, state} = ActivityFormatter.for_discord(activity)
    world_image = get_world_image(activity.world)

    {large_image, large_text, small_image} =
      case world_image do
        nil -> {"zwift_logo", nil, nil}
        image -> {image, activity.world, "zwift_logo"}
      end

    discord_activity = %{
      details: details,
      state: state,
      start_time: start_time,
      large_image: large_image,
      large_text: large_text,
      small_image: small_image,
      small_text: nil
    }

    Logger.debug("activity state: #{inspect(activity)}, start_time=#{start_time}")
    Logger.debug("updating Discord presence: #{inspect(discord_activity)}")
    Zdbeam.DiscordRPC.update_presence(discord_activity)
  end

  defp random_idle_message do
    [
      "Adjusting bike seat",
      "Adjusting fan speed",
      "Admiring the garage setup",
      "Browsing the map",
      "Choosing a route",
      "Filling water bottles",
      "Picking a kit",
      "Psyching up",
      "Queuing up music",
      "Selecting a bike",
      "Warming up"
    ]
    |> Enum.random()
  end

  defp get_world_image(world) when is_binary(world) do
    case String.downcase(world) do
      "makuri islands" -> "world_makuri"
      "new york" -> "world_newyork"
      "watopia" -> "world_watopia"
      # No images yet on Discord side
      # "france" -> "world_france"
      # "innsbruck" -> "world_innsbruck"
      # "london" -> "world_london"
      # "paris" -> "world_paris"
      # "richmond" -> "world_richmond"
      # "scotland" -> "world_scotland"
      # "yorkshire" -> "world_yorkshire"
      _ -> nil
    end
  end

  defp get_world_image(_), do: nil

  defp schedule_check do
    check_interval = Application.get_env(:zdbeam, :check_interval)
    Process.send_after(self(), :check_zwift, check_interval)
  end
end
