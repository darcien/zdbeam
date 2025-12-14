defmodule Zdbeam.LogSimulator do
  @moduledoc """
  Simulates log parsing for debugging activity detection.

  ## Examples

      mix zdbeam.test_log ~/Documents/Zwift/Logs/Log.txt
      mix zdbeam.test_log logs.txt --chunk-size 1000

      iex> LogSimulator.simulate_file("~/Documents/Zwift/Logs/Log.txt")
      :ok
  """

  alias Zdbeam.LogParser
  alias Zdbeam.LogPatterns

  @patterns LogPatterns.patterns()

  @doc """
  Simulates log parsing and shows state transitions.

  ## Options

    * `:chunk_size` - Lines per check (default: 600)

  ## Examples

      LogSimulator.simulate_file("~/Documents/Zwift/Logs/Log.txt")
      LogSimulator.simulate_file("logs.txt", chunk_size: 1000)
  """
  def simulate_file(path, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 600)

    with {:ok, expanded_path} <- expand_path(path),
         {:ok, content} <- File.read(expanded_path) do
      lines = String.split(content, "\n")

      IO.puts("log: #{expanded_path}")
      IO.puts("size: #{format_bytes(byte_size(content))}, lines: #{length(lines)}\n")

      simulate_checks(lines, chunk_size)

      :ok
    else
      {:error, :enoent} ->
        IO.puts("file_not_found: #{path}")
        {:error, :file_not_found}

      {:error, reason} ->
        IO.puts("read_error: #{inspect(reason)}")
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

  defp simulate_checks(lines, chunk_size) do
    IO.puts("simulating checks: #{chunk_size} lines/check\n")

    {final_state, state_changes} =
      lines
      |> Enum.chunk_every(chunk_size)
      |> Enum.with_index(1)
      |> Enum.reduce({nil, []}, fn {chunk, check_num}, {current_state, changes} ->
        new_state = LogParser.parse_log_lines(chunk, current_state)

        timestamp = extract_time(Enum.at(chunk, 0) || "")
        line_num = (check_num - 1) * chunk_size

        # Only record meaningful state changes (when formatted output differs)
        current_formatted = format_state(current_state)
        new_formatted = format_state(new_state)

        new_changes =
          if current_formatted != new_formatted do
            [
              %{
                check: check_num,
                from: current_state,
                to: new_state,
                timestamp: timestamp,
                line: line_num
              }
              | changes
            ]
          else
            changes
          end

        {new_state, new_changes}
      end)

    IO.puts("final state: #{format_state(final_state)}")
    IO.puts("state changes: #{length(state_changes)}\n")

    unless Enum.empty?(state_changes) do
      state_changes
      |> Enum.reverse()
      |> Enum.each(fn change ->
        IO.puts(
          "check #{change.check}: [#{change.timestamp}] L#{change.line}: #{format_state(change.from)} → #{format_state(change.to)}"
        )
      end)

      IO.puts("")
    end

    show_timeline(lines)
  end

  defp show_timeline(lines) do
    IO.puts("events:")

    events =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _idx} ->
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
        Enum.each(events, fn {line, idx} ->
          time = extract_time(line)
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
        world = LogParser.extract_world_from_activity_name(line)
        if world != "Unknown", do: " world=#{world}", else: ""

      :set_workout ->
        case LogParser.extract_workout_name(line) do
          nil -> ""
          workout -> " workout=#{workout}"
        end

      :setting_route ->
        case LogParser.extract_route_name(line) do
          nil -> ""
          route -> " route=#{route}"
        end

      event when event in [:pacer_joined, :pacer_left] ->
        case LogParser.extract_pacer_name_from_event(line) do
          nil -> ""
          name -> " pacer=#{name}"
        end

      event when event in [:completed_workout, :discard_activity, :end_activity] ->
        ""

      _ ->
        ""
    end
  end

  defp format_state(state) do
    case LogParser.format_activity(state) do
      {details, nil} -> details
      {details, type_label} -> "#{details} (#{type_label})"
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} bytes"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
end
