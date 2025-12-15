defmodule Zdbeam.ZwiftLogParser do
  @moduledoc """
  Parses Zwift log files to extract activity information.

  ## RoboPacer

  Zwift renamed "Pace Partner" to "RoboPacer" few years ago.
  Internally, the logs still refer to it as "PacePartner".

  Join event (multi-line block):
  ```
  [22:01:50] PacePartnerAnalytics:  --PacePartnerJoin--
  [22:01:50] PacePartnerAnalytics:    timestamp: "2025/12/11 11:01:50 UTC"
  [22:01:50] PacePartnerAnalytics:    pace_partner_name: "D. Maria"
  [22:01:50] PacePartnerAnalytics:    pace_partner_category: "D"
  [22:01:50] PacePartnerAnalytics:  --End PacePartnerJoin--
  ```

  Exit event (multi-line block):
  ```
  [22:04:33] PacePartnerAnalytics:  --PacePartnerRideSummary--
  [22:04:33] PacePartnerAnalytics:    pace_partner_exit: EXIT_RANGE
  [22:04:33] PacePartnerAnalytics:  --End PacePartnerRideSummary--
  ```

  ## Workout Completion

  When a workout is completed:
  ```
  [19:49:56] INFO LEVEL: [Workouts] WorkoutDatabase::HandleEvent(COMPLETED_WORKOUT): 4020009.000000
  ```

  This transitions the activity back to free ride mode.

  ## Activity End

  When an activity is properly saved and ended:
  ```
  [22:00:24] INFO LEVEL: [SaveActivityService] EndCurrentActivity with {activityName: Zwift - Endurance Building Blocks on Double Parked in New York, privacy: PUBLIC, hideProData: False}
  ```

  When an activity is discarded (not saved):
  ```
  [23:47:17] INFO LEVEL: [SaveActivityService] DeleteCurrentActivity with {activityName: Zwift - Mountain Mash in Watopia}
  ```

  Both patterns reset the activity to nil. Note that route changes may appear in logs after quit
  due to cleanup, but these are ignored when no activity is active.

  ## TODO
  - Extract actual start time from log timestamps to show accurate elapsed time
    even when the app starts mid-ride
  """

  alias Zdbeam.LogPatterns

  @type activity_type :: :free_ride | :workout | :robo_pacer

  @patterns LogPatterns.patterns()

  @doc """
  Parses log lines to extract current activity state.

  Returns a map with activity details or nil if no active activity.

  ## Examples

      iex> lines = [
      ...>   "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}"
      ...> ]
      iex> Zdbeam.ZwiftLogParser.parse_log_lines(lines)
      %{type: :free_ride, world: "Watopia", route: nil, workout_name: nil, pacer_name: nil}

  """
  def parse_log_lines(lines, initial_state \\ nil) do
    Enum.reduce(lines, initial_state, fn line, acc ->
      cond do
        String.contains?(line, @patterns.discard_activity) ->
          nil

        String.contains?(line, @patterns.end_activity) ->
          nil

        String.contains?(line, @patterns.save_activity) ->
          # Only treat as activity start if uploadTo3P: False (autosave, not final upload)
          if String.contains?(line, "uploadTo3P: False") do
            world = extract_world_from_activity_name(line)

            if acc do
              # Update existing activity with world info
              %{acc | world: world}
            else
              # New activity
              %{
                type: :free_ride,
                world: world,
                route: nil,
                workout_name: nil,
                pacer_name: nil
              }
            end
          else
            # uploadTo3P: True is final upload after EndCurrentActivity
            acc
          end

        String.contains?(line, @patterns.set_workout) ->
          workout_name = extract_workout_name(line)

          if acc do
            %{acc | type: :workout, workout_name: workout_name}
          else
            %{
              type: :workout,
              world: nil,
              route: nil,
              workout_name: workout_name,
              pacer_name: nil
            }
          end

        String.contains?(line, @patterns.completed_workout) ->
          case acc do
            %{type: :workout} -> %{acc | type: :free_ride, workout_name: nil}
            _ -> acc
          end

        String.contains?(line, @patterns.pacer_joined) ->
          if acc do
            pacer_name = extract_pacer_name_from_event(line)
            %{acc | type: :robo_pacer, pacer_name: pacer_name}
          else
            acc
          end

        String.contains?(line, @patterns.pacer_left) ->
          case acc do
            %{type: :robo_pacer} -> %{acc | type: :free_ride, pacer_name: nil}
            _ -> acc
          end

        String.contains?(line, @patterns.setting_route) ->
          # Ignore route changes when there's no active activity (post-quit cleanup)
          route = extract_route_name(line)
          if acc, do: %{acc | route: route}, else: acc

        true ->
          acc
      end
    end)
  end

  @doc """
  Extracts world name from activity save log line.

  ## Examples

      iex> line = "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}"
      iex> Zdbeam.ZwiftLogParser.extract_world_from_activity_name(line)
      "Watopia"

  """
  def extract_world_from_activity_name(line) do
    case Regex.run(~r/\{name:\s*Zwift - ([^,]+),/, line) do
      [_, world] -> String.trim(world)
      _ -> "Unknown"
    end
  end

  @doc """
  Extracts route name from route setting log line.

  ## Examples

      iex> line = "[23:19:29] INFO LEVEL: [Route] Setting Route:   The Classic"
      iex> Zdbeam.ZwiftLogParser.extract_route_name(line)
      "The Classic"

  """
  def extract_route_name(line) do
    case Regex.run(~r/Setting Route:\s*(.+)$/, line) do
      [_, route] -> String.trim(route)
      _ -> nil
    end
  end

  @doc """
  Extracts workout name from workout log line.

  ## Examples

      iex> line = "[21:34:41] INFO LEVEL: [Workouts] WorkoutDatabase::SetActiveWorkout(1. Ramp It Up!)"
      iex> Zdbeam.ZwiftLogParser.extract_workout_name(line)
      "1. Ramp It Up!"

  """
  def extract_workout_name(line) do
    case Regex.run(~r/SetActiveWorkout\(([^)]+)\)/, line) do
      [_, workout] -> String.trim(workout)
      _ -> nil
    end
  end

  @doc """
  Extracts pace partner name from structured event log line.

  ## Examples

      iex> line = "[22:01:50] DEBUG LEVEL: [StructuredEvents] Sending PacePartnerJoined structured event for D. Maria"
      iex> Zdbeam.ZwiftLogParser.extract_pacer_name_from_event(line)
      "D. Maria"

      iex> line = "[22:04:33] DEBUG LEVEL: [StructuredEvents] Sending PacePartnerLeft structured event for D. Maria (exit: EXIT_RANGE)"
      iex> Zdbeam.ZwiftLogParser.extract_pacer_name_from_event(line)
      "D. Maria"

  """
  def extract_pacer_name_from_event(line) do
    case Regex.run(~r/structured event for ([^\(]+)/, line) do
      [_, name] -> String.trim(name)
      _ -> nil
    end
  end
end
