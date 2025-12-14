defmodule Zdbeam.ZwiftReaderTest do
  use ExUnit.Case
  alias Zdbeam.LogParser

  describe "parse_log_lines/1" do
    test "detects activity start from SaveActivity log line" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False, fitFileNameToUpload: /Users/darcien/Documents/Zwift/Activities/inProgressActivity.fit, fitFileNameShort: 2025-12-10-23-19-29.fit}"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == %{
               type: :free_ride,
               world: "Watopia",
               route: nil,
               workout_name: nil,
               pacer_name: nil
             }
    end

    test "detects route change" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[23:19:29] INFO LEVEL: [Route] Setting Route:   The Classic"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == %{
               type: :free_ride,
               world: "Watopia",
               route: "The Classic",
               workout_name: nil,
               pacer_name: nil
             }
    end

    test "detects activity end (discard)" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[23:47:17] INFO LEVEL: [SaveActivityService] DeleteCurrentActivity: Close FIT File",
        "[23:47:17] INFO LEVEL: [SaveActivityService] DeleteCurrentActivity with {activityName: Zwift - Mountain Mash in Watopia}"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == nil
    end

    test "detects activity end (save/quit)" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[22:00:24] INFO LEVEL: [SaveActivityService] EndCurrentActivity with {activityName: Zwift - Endurance Building Blocks on Double Parked in New York, privacy: PUBLIC, hideProData: False}",
        "[22:00:24] INFO LEVEL: [SaveActivityService] FinalizeCurrentActivity Close FIT File"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == nil
    end

    test "detects activity end with route info" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[23:19:29] INFO LEVEL: [Route] Setting Route:   The Classic",
        "[23:24:52] INFO LEVEL: [SaveActivityService] DeleteCurrentActivity: Close FIT File",
        "[23:24:52] INFO LEVEL: [SaveActivityService] DeleteCurrentActivity with {activityName: Zwift - The Classic in Watopia}"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == nil
    end

    test "ignores post-quit route changes" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[22:00:24] INFO LEVEL: [SaveActivityService] EndCurrentActivity with {activityName: Zwift - Watopia, privacy: PUBLIC, hideProData: False}",
        "[22:03:09] INFO LEVEL: [Route] Setting Route:   Double Parked"
      ]

      result = LogParser.parse_log_lines(lines)

      # Route change after EndCurrentActivity should be ignored (no activity active)
      assert result == nil
    end

    test "handles multiple route changes" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[23:19:29] INFO LEVEL: [Route] Setting Route:   The Classic",
        "[23:25:00] INFO LEVEL: [Route] Setting Route:   Volcano Circuit"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == %{
               type: :free_ride,
               world: "Watopia",
               route: "Volcano Circuit",
               workout_name: nil,
               pacer_name: nil
             }
    end

    test "extracts different world names" do
      test_cases = [
        {"Zwift - Watopia", "Watopia"},
        {"Zwift - France", "France"},
        {"Zwift - London", "London"},
        {"Zwift - Makuri Islands", "Makuri Islands"},
        {"Zwift - Scotland", "Scotland"}
      ]

      for {activity_name, expected_world} <- test_cases do
        lines = [
          "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: #{activity_name}, uploadTo3P: False}"
        ]

        result = LogParser.parse_log_lines(lines)

        assert result.world == expected_world,
               "Expected world '#{expected_world}' from activity name '#{activity_name}', got '#{result.world}'"
      end
    end

    test "ignores unrelated log lines" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[23:19:30] Loading WAD file 'assets/Environment/Road/RideLondonRoad/RideLondonRoad3.wad' with file.",
        "[23:19:31] ERROR LEVEL: [LOADER] LOADER_LoadGdeFile_LEAN() Unable to load texture file",
        "[23:19:32] INFO LEVEL: [ActivityRecommendations] Using player bike w/kg: 2.31",
        "[23:19:33] INFO LEVEL: [Route] Setting Route:   The Classic"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == %{
               type: :free_ride,
               world: "Watopia",
               route: "The Classic",
               workout_name: nil,
               pacer_name: nil
             }
    end

    test "returns nil when no activity detected" do
      lines = [
        "[23:19:30] Loading WAD file 'assets/Environment/Road/RideLondonRoad/RideLondonRoad3.wad' with file.",
        "[23:19:31] ERROR LEVEL: [LOADER] LOADER_LoadGdeFile_LEAN() Unable to load texture file"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == nil
    end

    test "route change without active activity does nothing" do
      lines = [
        "[23:19:29] INFO LEVEL: [Route] Setting Route:   The Classic"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == nil
    end

    test "detects workout start" do
      lines = [
        "[21:34:41] Training Plan - Setting sport to CYCLING",
        "[21:34:41] INFO LEVEL: [Workouts] WorkoutDatabase::SetActiveWorkout(1. Ramp It Up!)",
        "[21:34:41] Got Notable Moment: STARTED WORKOUT"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == %{
               type: :workout,
               world: nil,
               route: nil,
               workout_name: "1. Ramp It Up!",
               pacer_name: nil
             }
    end

    test "detects workout after activity started" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[21:34:41] INFO LEVEL: [Workouts] WorkoutDatabase::SetActiveWorkout(1. Ramp It Up!)"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == %{
               type: :workout,
               world: "Watopia",
               route: nil,
               workout_name: "1. Ramp It Up!",
               pacer_name: nil
             }
    end

    test "workout with route change shows workout name" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[21:34:41] INFO LEVEL: [Workouts] WorkoutDatabase::SetActiveWorkout(1. Ramp It Up!)",
        "[23:19:29] INFO LEVEL: [Route] Setting Route:   The Classic"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == %{
               type: :workout,
               world: "Watopia",
               route: "The Classic",
               workout_name: "1. Ramp It Up!",
               pacer_name: nil
             }
    end

    test "detects robo pacer join" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[22:01:50] DEBUG LEVEL: [StructuredEvents] Sending PacePartnerJoined structured event for D. Maria"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == %{
               type: :robo_pacer,
               world: "Watopia",
               route: nil,
               workout_name: nil,
               pacer_name: "D. Maria"
             }
    end

    test "detects robo pacer exit" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[22:01:50] DEBUG LEVEL: [StructuredEvents] Sending PacePartnerJoined structured event for D. Maria",
        "[22:04:33] DEBUG LEVEL: [StructuredEvents] Sending PacePartnerLeft structured event for D. Maria (exit: EXIT_RANGE)"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == %{
               type: :free_ride,
               world: "Watopia",
               route: nil,
               workout_name: nil,
               pacer_name: nil
             }
    end

    test "detects robo pacer with route" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[23:19:29] INFO LEVEL: [Route] Setting Route:   Triple Flat Loops",
        "[22:01:50] DEBUG LEVEL: [StructuredEvents] Sending PacePartnerJoined structured event for D. Maria"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == %{
               type: :robo_pacer,
               world: "Watopia",
               route: "Triple Flat Loops",
               workout_name: nil,
               pacer_name: "D. Maria"
             }
    end

    test "detects workout completion and transitions to free ride" do
      lines = [
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}",
        "[21:34:41] INFO LEVEL: [Workouts] WorkoutDatabase::SetActiveWorkout(Endurance Building Blocks)",
        "[19:49:56] INFO LEVEL: [Workouts] WorkoutDatabase::HandleEvent(COMPLETED_WORKOUT): 4020009.000000"
      ]

      result = LogParser.parse_log_lines(lines)

      assert result == %{
               type: :free_ride,
               world: "Watopia",
               route: nil,
               workout_name: nil,
               pacer_name: nil
             }
    end

    test "workout completion with current state transitions back to free ride" do
      # Simulate maintaining state between checks
      initial_state = %{
        type: :workout,
        world: "New York",
        route: "Double Parked",
        workout_name: "Endurance Building Blocks",
        pacer_name: nil
      }

      lines = [
        "[19:49:56] Requesting Notable Moment Screenshot, type=FINISHED WORKOUT, delay=3.50, distance=-1.00",
        "[19:49:56] INFO LEVEL: [Workouts] WorkoutDatabase::HandleEvent(COMPLETED_WORKOUT): 4020009.000000"
      ]

      result = LogParser.parse_log_lines(lines, initial_state)

      assert result == %{
               type: :free_ride,
               world: "New York",
               route: "Double Parked",
               workout_name: nil,
               pacer_name: nil
             }
    end
  end

  describe "extract_world_from_activity_name/1" do
    test "extracts world name from activity line" do
      line =
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Watopia, uploadTo3P: False}"

      result = LogParser.extract_world_from_activity_name(line)

      assert result == "Watopia"
    end

    test "extracts world name with spaces" do
      line =
        "[23:19:29] INFO LEVEL: [SaveActivityService] ZNet::SaveActivity calling zwift_network::save_activity with {name: Zwift - Makuri Islands, uploadTo3P: False}"

      result = LogParser.extract_world_from_activity_name(line)

      assert result == "Makuri Islands"
    end

    test "returns Unknown for malformed line" do
      line = "[23:19:29] Some random log line"

      result = LogParser.extract_world_from_activity_name(line)

      assert result == "Unknown"
    end
  end

  describe "extract_route_name/1" do
    test "extracts route name" do
      line = "[23:19:29] INFO LEVEL: [Route] Setting Route:   The Classic"

      result = LogParser.extract_route_name(line)

      assert result == "The Classic"
    end

    test "extracts route name with extra spaces" do
      line = "[23:19:29] INFO LEVEL: [Route] Setting Route:   Volcano Circuit  "

      result = LogParser.extract_route_name(line)

      assert result == "Volcano Circuit"
    end

    test "returns nil for malformed line" do
      line = "[23:19:29] Some random log line"

      result = LogParser.extract_route_name(line)

      assert result == nil
    end
  end

  describe "extract_pacer_name_from_event/1" do
    test "extracts pace partner name from join event" do
      line =
        "[22:01:50] DEBUG LEVEL: [StructuredEvents] Sending PacePartnerJoined structured event for D. Maria"

      result = LogParser.extract_pacer_name_from_event(line)

      assert result == "D. Maria"
    end

    test "extracts pace partner name from left event" do
      line =
        "[22:04:33] DEBUG LEVEL: [StructuredEvents] Sending PacePartnerLeft structured event for D. Maria (exit: EXIT_RANGE)"

      result = LogParser.extract_pacer_name_from_event(line)

      assert result == "D. Maria"
    end

    test "extracts pace partner name with single letter" do
      line =
        "[22:01:50] DEBUG LEVEL: [StructuredEvents] Sending PacePartnerJoined structured event for C. Cadence"

      result = LogParser.extract_pacer_name_from_event(line)

      assert result == "C. Cadence"
    end

    test "returns nil for malformed line" do
      line = "[23:19:29] Some random log line"

      result = LogParser.extract_pacer_name_from_event(line)

      assert result == nil
    end
  end

  describe "extract_workout_name/1" do
    test "extracts workout name" do
      line =
        "[21:34:41] INFO LEVEL: [Workouts] WorkoutDatabase::SetActiveWorkout(1. Ramp It Up!)"

      result = LogParser.extract_workout_name(line)

      assert result == "1. Ramp It Up!"
    end

    test "extracts workout name with special characters" do
      line =
        "[21:34:41] INFO LEVEL: [Workouts] WorkoutDatabase::SetActiveWorkout(FTP Test - 20min)"

      result = LogParser.extract_workout_name(line)

      assert result == "FTP Test - 20min"
    end

    test "returns nil for malformed line" do
      line = "[23:19:29] Some random log line"

      result = LogParser.extract_workout_name(line)

      assert result == nil
    end
  end
end
