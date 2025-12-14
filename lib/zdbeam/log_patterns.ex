defmodule Zdbeam.LogPatterns do
  @moduledoc """
  Zwift log pattern strings for matching activity events.

  These patterns are used by both the log parser and simulator
  to detect activity state changes in Zwift log files.
  """

  @patterns %{
    discard_activity: "DeleteCurrentActivity with {activityName:",
    end_activity: "[SaveActivityService] EndCurrentActivity with {activityName:",
    save_activity:
      "[SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name:",
    set_workout: "[Workouts] WorkoutDatabase::SetActiveWorkout(",
    completed_workout: "[Workouts] WorkoutDatabase::HandleEvent(COMPLETED_WORKOUT)",
    pacer_joined: "Sending PacePartnerJoined structured event for",
    pacer_left: "Sending PacePartnerLeft structured event for",
    setting_route: "[Route] Setting Route:"
  }

  @doc """
  Returns all log pattern strings as a map.

  ## Examples

      iex> Zdbeam.LogPatterns.patterns()
      %{
        save_activity: "[SaveActivityService] ZNet::SaveActivity...",
        set_workout: "[Workouts] WorkoutDatabase::SetActiveWorkout(",
        ...
      }

  """
  def patterns, do: @patterns

  @doc """
  Returns a specific pattern string.

  ## Examples

      iex> Zdbeam.LogPatterns.get(:save_activity)
      "[SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name:"

      iex> Zdbeam.LogPatterns.get(:set_workout)
      "[Workouts] WorkoutDatabase::SetActiveWorkout("

  """
  def get(key), do: Map.get(@patterns, key)
end
