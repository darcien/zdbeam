defmodule Zdbeam.LogSimulator do
  @moduledoc """
  Simulates log parsing for debugging activity detection.

  ## Examples

      mix zdbeam.test_log ~/Documents/Zwift/Logs/Log.txt
      mix zdbeam.test_log logs.txt --check-interval 5

      iex> LogSimulator.simulate_file("~/Documents/Zwift/Logs/Log.txt")
      :ok
  """

  alias Zdbeam.ActivityFormatter
  alias Zdbeam.ZwiftLogPatterns
  alias Zdbeam.ZwiftLogParser

  @patterns ZwiftLogPatterns.patterns()
  @default_check_interval 5

  @doc """
  Simulates log parsing and shows state transitions.

  ## Options

    * `:check_interval` - Seconds between checks (default: 5)

  ## Examples

      LogSimulator.simulate_file("~/Documents/Zwift/Logs/Log.txt")
      LogSimulator.simulate_file("logs.txt", check_interval: 10)
  """
  def simulate_file(path, opts \\ []) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)

    with {:ok, expanded_path} <- expand_path(path),
         {:ok, content} <- File.read(expanded_path) do
      lines = String.split(content, "\n")

      IO.puts("log: #{expanded_path}")
      IO.puts("size: #{format_bytes(byte_size(content))}, lines: #{length(lines)}\n")

      simulate_checks(lines, check_interval)

      :ok
    else
      {:error, :enoent} ->
        IO.puts("file not found: #{path}")
        {:error, :file_not_found}

      {:error, reason} ->
        IO.puts("read error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp expand_path(path) do
    expanded = Path.expand(path)

    if File.exists?(expanded) do
      {:ok, expanded}
    else
      {:error, :enoent}
    end
  end

  defp simulate_checks(lines, check_interval) do
    IO.puts("simulating checks: every #{check_interval}s\n")

    lines_with_time = parse_timestamps(lines)

    case lines_with_time do
      [] ->
        IO.puts("no timestamps found")
        :ok

      lines_with_time ->
        {start_time, _, _} = hd(lines_with_time)
        {end_time, _, _} = List.last(lines_with_time)

        duration = time_diff_seconds(start_time, end_time)
        IO.puts("time range: #{start_time} → #{end_time} (#{format_duration(duration)})\n")

        {final_state, state_changes} =
          run_time_based_checks(lines_with_time, start_time, check_interval)

        IO.puts("final state: #{format_state(final_state)}")
        IO.puts("state changes: #{length(state_changes)}\n")

        unless Enum.empty?(state_changes) do
          state_changes
          |> Enum.reverse()
          |> Enum.each(fn change ->
            IO.puts(
              "check #{change.check}: [#{change.timestamp}] #{format_state(change.from)} → #{format_state(change.to)}"
            )
          end)

          IO.puts("")
        end

        show_timeline(lines_with_time)
    end
  end

  defp parse_timestamps(lines) do
    for {line, idx} <- Enum.with_index(lines),
        time = extract_time(line),
        time != "??:??:??",
        do: {time, line, idx}
  end

  defp run_time_based_checks(lines_with_time, _start_time, check_interval) do
    {first_time, _, _} = hd(lines_with_time)
    {last_time, _, _} = List.last(lines_with_time)

    check_times = generate_check_times(first_time, last_time, check_interval)

    {final_state, state_changes, _} =
      check_times
      |> Enum.with_index(1)
      |> Enum.reduce({nil, [], 0}, fn {{_check_time, next_check_time}, check_num},
                                      {current_state, changes, last_idx} ->
        new_lines =
          lines_with_time
          |> Enum.drop(last_idx)
          |> Enum.take_while(fn {line_time, _line, _idx} ->
            time_to_seconds(line_time) < time_to_seconds(next_check_time)
          end)

        lines_to_parse = Enum.map(new_lines, fn {_time, line, _idx} -> line end)

        new_state =
          case lines_to_parse do
            [] -> current_state
            lines -> ZwiftLogParser.parse_log_lines(lines, current_state)
          end

        new_changes =
          if format_state(current_state) != format_state(new_state) do
            [
              %{
                check: check_num,
                from: current_state,
                to: new_state,
                timestamp: next_check_time
              }
              | changes
            ]
          else
            changes
          end

        {new_state, new_changes, last_idx + length(new_lines)}
      end)

    {final_state, state_changes}
  end

  defp generate_check_times(start_time, end_time, interval) do
    start_seconds = time_to_seconds(start_time)
    end_seconds = time_to_seconds(end_time)

    check_times =
      Stream.iterate(start_seconds, &(&1 + interval))
      |> Enum.take_while(&(&1 <= end_seconds))
      |> Enum.map(&seconds_to_time/1)

    check_times
    |> Enum.zip(Enum.drop(check_times, 1) ++ [end_time])
  end

  defp time_to_seconds(time) do
    case String.split(time, ":") do
      [h, m, s] ->
        String.to_integer(h) * 3600 + String.to_integer(m) * 60 + String.to_integer(s)

      _ ->
        0
    end
  end

  defp seconds_to_time(seconds) do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    s = rem(seconds, 60)

    "#{String.pad_leading(to_string(h), 2, "0")}:#{String.pad_leading(to_string(m), 2, "0")}:#{String.pad_leading(to_string(s), 2, "0")}"
  end

  defp time_diff_seconds(start_time, end_time) do
    time_to_seconds(end_time) - time_to_seconds(start_time)
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) when seconds < 3600 do
    "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
  end

  defp format_duration(seconds) do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    "#{h}h #{m}m"
  end

  defp show_timeline(lines_with_time) do
    IO.puts("events:")

    events =
      lines_with_time
      |> Enum.filter(fn {_time, line, _idx} ->
        String.contains?(line, @patterns.save_activity) or
          String.contains?(line, @patterns.set_workout) or
          String.contains?(line, @patterns.completed_workout) or
          String.contains?(line, @patterns.setting_route) or
          String.contains?(line, @patterns.pacer_joined) or
          String.contains?(line, @patterns.pacer_left) or
          String.contains?(line, @patterns.discard_activity) or
          String.contains?(line, @patterns.end_activity)
      end)

    case events do
      [] ->
        IO.puts("  none")

      events ->
        Enum.each(events, fn {time, line, idx} ->
          event_type = classify_event(line)
          details = extract_event_details(line, event_type)

          IO.puts("  [#{time}] L#{idx}: #{event_type}#{details}")
        end)
    end
  end

  defp extract_time(line) do
    case Regex.run(~r/\[(\d+:\d+:\d+)\]/, line) do
      [_, time] -> time
      _ -> "??:??:??"
    end
  end

  defp classify_event(line) do
    cond do
      String.contains?(line, @patterns.save_activity) ->
        :save_activity

      String.contains?(line, @patterns.set_workout) ->
        :set_workout

      String.contains?(line, @patterns.completed_workout) ->
        :completed_workout

      String.contains?(line, @patterns.setting_route) ->
        :setting_route

      String.contains?(line, @patterns.pacer_joined) ->
        :pacer_joined

      String.contains?(line, @patterns.pacer_left) ->
        :pacer_left

      String.contains?(line, @patterns.discard_activity) ->
        :discard_activity

      String.contains?(line, @patterns.end_activity) ->
        :end_activity

      true ->
        :unknown
    end
  end

  defp extract_event_details(line, event_type) do
    case event_type do
      :save_activity ->
        world = ZwiftLogParser.extract_world_from_activity_name(line)
        if world != "Unknown", do: ~s( world="#{world}"), else: ""

      :set_workout ->
        case ZwiftLogParser.extract_workout_name(line) do
          nil -> ""
          workout -> ~s( workout="#{workout}")
        end

      :setting_route ->
        case ZwiftLogParser.extract_route_name(line) do
          nil -> ""
          route -> ~s( route="#{route}")
        end

      event when event in [:pacer_joined, :pacer_left] ->
        case ZwiftLogParser.extract_pacer_name_from_event(line) do
          nil -> ""
          name -> ~s( pacer="#{name}")
        end

      event when event in [:completed_workout, :discard_activity, :end_activity] ->
        ""

      _ ->
        ""
    end
  end

  defp format_state(state) do
    ActivityFormatter.for_log(state)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} bytes"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
end
