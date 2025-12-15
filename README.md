# zdbeam

CLI tool that adds Discord Rich Presence integration for Zwift.

## Why

I have this itch to make something with Elixir.
And I'm in the mood for indoor cycling.
So why not?

## Features

- Almost real-time activity monitoring by polling Zwift log file
- Standalone binary distribution
- Pure Elixir implementation

## How It Works

1. Monitors Zwift process status
2. Reads activity data from `~/Documents/Zwift/Logs/Log.txt`
3. Parses world, route, workout, and RoboPacer information
4. Updates Discord Rich Presence via local IPC connection

Zwift, Discord, and zdbeam must all be running on the same machine.

In theory we can have Zwift and Discord run on different machines,
have zdbeam run on each machine, have each zdbeam connect to each other
via `Node.connect/1` and have Discord RPC over the network.

I have no need for that at the moment though, so it's unimplemented.

## Screenshots

TBA.

## Platform Support

Currently supports macOS only.
For other platforms like Linux or Windows, might work with slight changes but have not been tested.

## Prerequisites

### Users

- macOS (Apple Silicon)
- Discord Desktop App
- Zwift

### Developers

- Elixir 1.19.2+
- Erlang/OTP 28.2+
- Zig 0.15.2 (for building binary with Burrito)
- XZ (for building binary with Burrito)

## Installation

### Binary Release

No releases available yet.
I'm not interested in code-signing at the moment.

### Building from Source

```sh
git clone git@github.com:darcien/zdbeam.git
cd zdbeam
mix deps.get
MIX_ENV=prod mix release zdbeam
```

Binary output: `burrito_out/zdbeam_macos`

## Discord Application Setup

1. Create application at https://discord.com/developers/applications
2. Copy Application ID from General Information tab
3. (Optional) Add Rich Presence assets under "Rich Presence" → "Art Assets":
   - `zwift_logo` - Main application icon
   - `world_watopia`, `world_london`, etc. - World-specific icons


## Usage

```sh
zdbeam --app-id "YOUR_DISCORD_APP_ID"
```

```sh
zdbeam \
  --app-id "YOUR_DISCORD_APP_ID" \
  --check-interval 15 \
  --log-level debug
```

### Example Output

```
$ zdbeam --app-id "0000000000000000000"
starting
app_id: 0000000000000000000
check_interval: 5s
log_level: info

[info] starting application
[info] starting Zwift activity reader
[info] initializing Discord RPC: app_id=0000000000000000000
[info] connected to Discord IPC
[info] handshake successful
[info] Zwift detected as running
[info] presence updated: %{"cmd" => "SET_ACTIVITY", "data" => %{"application_id" => "0000000000000000000", "assets" => %{"large_image" => "1449021117804183602", "large_text" => "Filling water bottles"}, "details" => "Picking a kit", "metadata" => %{}, "name" => "Zwift", "platform" => "desktop", "state" => "Idling", "timestamps" => %{"start" => 1765695545000}, "type" => 0}, "evt" => nil, "nonce" => "89f459c765c5a880f6a243a5dbb01af9"}
[info] activity changed: %{type: :workout, world: "Watopia", route: "Loopin Lava", workout_name: "Active Recovery", pacer_name: nil}
```

TODO: make the info easier to read

## Options

```
-a, --app-id <id>           Discord Application ID (required)
-i, --check-interval <sec>  Polling interval in seconds (default: 5)
-l, --log-level <level>     Log level: debug|info|warning|error (default: info)
-t, --test-mode             Enable test mode with hardcoded activity
--test-log <path>           Simulate parsing a log file for debugging
-h, --help                  Display help message
-v, --version               Display version information
```

## Development

### Setup

```sh
mix deps.get
mix test
mix run --no-halt -- --app-id "YOUR_APP_ID" --log-level debug
```

### Debugging Activity Detection

If your activity isn't being detected properly, you can simulate parsing a log file:

```sh
# Using the built binary
zdbeam --test-log ~/Documents/Zwift/Logs/Log.txt

# During development
mix zdbeam.test_log ~/Documents/Zwift/Logs/Log.txt
```

This will show:
- How the parser processes your log file
- State transitions (idle → active → workout → etc.)
- Timeline of key events (set_workout, setting_route, etc.)

Example output:
```
mix zdbeam.test_log ~/Documents/Zwift/Logs/Log.txt
log: /Users/darcien/Documents/Zwift/Logs/Log.txt
size: 4.6 MB, lines: 53622

simulating checks: 600 lines/check

final state: Idling
state changes: 3

check 11: [18:00:03] L6000: Idling → Active Recovery (Workout)
check 24: [19:58:26] L13800: Active Recovery (Workout) → Loopin Lava, Watopia (Free Ride)
check 25: [20:02:46] L14400: Loopin Lava, Watopia (Free Ride) → Idling

events:
  [18:03:43] L6146: set_workout workout=Active Recovery
  [18:03:44] L6160: setting_route route=Loopin Lava
  [18:03:44] L6196: save_activity world=Watopia
  [18:03:50] L6401: setting_route route=Loopin Lava
  [18:06:38] L6928: save_activity world=Watopia
  ...
  [19:57:23] L13733: save_activity world=Watopia
  [20:02:06] L14098: completed_workout
  [20:02:06] L14108: save_activity world=Watopia
  [20:03:04] L14877: end_activity
```

### Building

```sh
MIX_ENV=prod mix build.prod
```

Binary output: `burrito_out/zdbeam_macos`

### Project Structure

```
lib/
├── zdbeam.ex                   # Public API module
└── zdbeam/
    ├── application.ex          # OTP Application supervisor & CLI
    ├── discord_rpc.ex          # Discord RPC client (GenServer)
    ├── log_parser.ex           # Log file parser
    ├── log_patterns.ex         # Log pattern matching rules
    ├── log_simulator.ex        # Log parsing simulator for debugging
    └── zwift_reader.ex         # Zwift activity monitor (GenServer)
```

## License

MIT License. See [LICENSE](LICENSE) for details.

Images in `assets/` are from [Zwift media kits](https://news.zwift.com/en-WW/assets/227831/) and used to display Zwift branding in Discord Rich Presence.

## AI Usage Disclaimer

Development in this repository makes heavy use of AI (mostly Claude Sonnet 4.5).
The resulting code is manually reviewed, tested, and modified as needed by a human.
(I swear I'm not a robot, [proof of humanhood][not-a-robot] available upon request.)

[not-a-robot]: https://neal.fun/not-a-robot/
