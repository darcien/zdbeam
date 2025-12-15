defmodule Zdbeam.ActivityFormatter do
  @moduledoc """
  Formats activity states for display.

  Provides formatting for both application logging and Discord Rich Presence.
  """

  @doc """
  Formats an activity state into a concise log message.

  Returns a brief string using key=value format for structured logging.

  ## Examples

      iex> Zdbeam.ActivityFormatter.for_log(nil)
      "idling"

      iex> activity = %{type: :workout, workout_name: "FTP Test"}
      iex> Zdbeam.ActivityFormatter.for_log(activity)
      "workout name=\"FTP Test\""

      iex> activity = %{type: :free_ride, world: "Watopia", route: "Volcano Circuit"}
      iex> Zdbeam.ActivityFormatter.for_log(activity)
      "free_ride route=\"Volcano Circuit\" world=\"Watopia\""

      iex> activity = %{type: :robo_pacer, pacer_name: "Coco", route: "Flat Route"}
      iex> Zdbeam.ActivityFormatter.for_log(activity)
      "robo_pacer name=\"Coco\" route=\"Flat Route\""

  """
  def for_log(nil), do: "idling"

  def for_log(activity) do
    case activity.type do
      :workout ->
        name = activity.workout_name || "working hard"
        ~s(workout name="#{name}")

      :robo_pacer ->
        parts =
          [
            activity.pacer_name && ~s(name="#{activity.pacer_name}"),
            activity.route && ~s(route="#{activity.route}")
          ]
          |> Enum.reject(&is_nil/1)

        case parts do
          [] -> "robo_pacer"
          _ -> "robo_pacer " <> Enum.join(parts, " ")
        end

      :free_ride ->
        parts =
          [
            activity.route && ~s(route="#{activity.route}"),
            activity.world && ~s(world="#{activity.world}")
          ]
          |> Enum.reject(&is_nil/1)

        case parts do
          [] -> "free_ride"
          _ -> "free_ride " <> Enum.join(parts, " ")
        end

      :event ->
        case activity.event_name do
          nil -> "event"
          name -> ~s(event name="#{name}")
        end
    end
  end

  @doc """
  Formats an activity state for Discord Rich Presence display.

  Returns a tuple of `{details, state}` where:
  - `details` is the main activity description (top line in Discord)
  - `state` is the activity type label (bottom line in Discord)

  Returns `{details, nil}` when no type label is applicable (e.g., idling).

  ## Examples

      iex> Zdbeam.ActivityFormatter.for_discord(nil)
      {"Idling", nil}

      iex> activity = %{type: :workout, workout_name: "FTP Test"}
      iex> Zdbeam.ActivityFormatter.for_discord(activity)
      {"FTP Test", "Workout"}

      iex> activity = %{type: :free_ride, world: "Watopia", route: "Volcano Circuit"}
      iex> Zdbeam.ActivityFormatter.for_discord(activity)
      {"Volcano Circuit, Watopia", "Free Ride"}

  """
  def for_discord(nil), do: {"Idling", nil}

  def for_discord(activity) do
    case activity.type do
      :workout ->
        details = activity.workout_name || "Working Hard"
        {details, "Workout"}

      :robo_pacer ->
        details =
          case {activity.pacer_name, activity.route} do
            {nil, nil} -> "RoboPacer"
            {nil, route} -> route
            {name, nil} -> name
            {name, route} -> "#{name} @ #{route}"
          end

        {details, "RoboPacer"}

      :free_ride ->
        details =
          case {activity.world, activity.route} do
            {nil, nil} -> "Lost in Zwift"
            {world, nil} -> world
            {nil, route} -> route
            {world, route} -> "#{route}, #{world}"
          end

        {details, "Free Ride"}

      :event ->
        details = activity.event_name || "Event"
        {details, "Event"}
    end
  end
end
