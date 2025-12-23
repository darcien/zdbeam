defmodule Zdbeam.ActivityFormatterTest do
  use ExUnit.Case
  doctest Zdbeam.ActivityFormatter

  alias Zdbeam.ActivityFormatter

  describe "for_log/1 edge cases" do
    test "workout with nil name" do
      activity = %{type: :workout, workout_name: nil}
      assert ActivityFormatter.for_log(activity) == ~s(workout name="working hard")
    end

    test "robo_pacer with only name" do
      activity = %{type: :robo_pacer, pacer_name: "Coco", route: nil}
      assert ActivityFormatter.for_log(activity) == ~s(robo_pacer name="Coco")
    end

    test "robo_pacer with only route" do
      activity = %{type: :robo_pacer, pacer_name: nil, route: "Flat Route"}
      assert ActivityFormatter.for_log(activity) == ~s(robo_pacer route="Flat Route")
    end

    test "robo_pacer with neither name nor route" do
      activity = %{type: :robo_pacer, pacer_name: nil, route: nil}
      assert ActivityFormatter.for_log(activity) == "robo_pacer"
    end

    test "free_ride with only world" do
      activity = %{type: :free_ride, world: "Watopia", route: nil}
      assert ActivityFormatter.for_log(activity) == ~s(free_ride world="Watopia")
    end

    test "free_ride with only route" do
      activity = %{type: :free_ride, world: nil, route: "Volcano Circuit"}
      assert ActivityFormatter.for_log(activity) == ~s(free_ride route="Volcano Circuit")
    end

    test "free_ride with neither world nor route" do
      activity = %{type: :free_ride, world: nil, route: nil}
      assert ActivityFormatter.for_log(activity) == "free_ride"
    end
  end

  describe "for_discord/1 edge cases" do
    test "workout with nil name" do
      activity = %{type: :workout, workout_name: nil}
      assert ActivityFormatter.for_discord(activity) == {"Working Hard", "Workout"}
    end

    test "robo_pacer with name and route" do
      activity = %{type: :robo_pacer, pacer_name: "Coco", route: "Flat Route"}
      assert ActivityFormatter.for_discord(activity) == {"Coco @ Flat Route", "RoboPacer"}
    end

    test "robo_pacer with only name" do
      activity = %{type: :robo_pacer, pacer_name: "Coco", route: nil}
      assert ActivityFormatter.for_discord(activity) == {"Coco", "RoboPacer"}
    end

    test "robo_pacer with only route" do
      activity = %{type: :robo_pacer, pacer_name: nil, route: "Flat Route"}
      assert ActivityFormatter.for_discord(activity) == {"Flat Route", "RoboPacer"}
    end

    test "robo_pacer with neither name nor route" do
      activity = %{type: :robo_pacer, pacer_name: nil, route: nil}
      assert ActivityFormatter.for_discord(activity) == {"RoboPacer", "RoboPacer"}
    end

    test "free_ride with only world" do
      activity = %{type: :free_ride, world: "Watopia", route: nil}
      assert ActivityFormatter.for_discord(activity) == {"Watopia", "Free Ride"}
    end

    test "free_ride with only route" do
      activity = %{type: :free_ride, world: nil, route: "Volcano Circuit"}
      assert ActivityFormatter.for_discord(activity) == {"Volcano Circuit", "Free Ride"}
    end

    test "free_ride with neither world nor route" do
      activity = %{type: :free_ride, world: nil, route: nil}
      assert ActivityFormatter.for_discord(activity) == {"Lost in Zwift", "Free Ride"}
    end
  end
end
