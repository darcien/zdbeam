# zdbeam

Beam your [Zwift][zwift] activity to [Discord Rich Presence][discord]. Ride on the [BEAM (Erlang VM)][BEAM].

[zwift]: https://www.zwift.com
[discord]: https://discord.com/developers/docs/rich-presence/overview
[BEAM]: https://en.wikipedia.org/wiki/BEAM_(Erlang_virtual_machine)

## Why

I have this itch to make something with Elixir.
And I'm in the mood for indoor cycling.
So why not?

## Features

- Almost real-time activity monitoring by polling Zwift log file
- Standalone binary distribution
- Pure Elixir implementation

## How It Works

1. Monitor Zwift process status
2. Poll activity data from `~/Documents/Zwift/Logs/Log.txt`
3. Detect notable events: route changes, workouts, RoboPacer rides
4. Update Discord Rich Presence via local IPC

Zwift, Discord, and zdbeam must all be running on the same machine.

## Non-Goals

- Broadcasting detailed numbers like power, heart rate, cadence is out of scope.
  Not interested in broadcasting private data.

## Future Possibilities

### Distributed Setup

In theory, we could run Zwift and Discord on different machines with zdbeam instances
on each, connecting via `Node.connect/1` for distributed Discord RPC.

I have no need for this at the moment, so it's unimplemented.

### Alternative Activity Sources

Instead of polling the Zwift log file, pretending to be a Zwift Companion app
might also work.

But reverse engineering a mobile app is more involved than parsing a log file,
and I don't see any advantage to that approach at the moment.

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

Prebuilt binaries are not provided.
I'm not interested in code-signing at the moment.

### Building from Source

See the [Development](#development) section below for build instructions.

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

[info] application started
[info] Zwift monitor started
[info] Discord RPC ready
[info] Zwift started
```


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
```

### Running

```sh
mix run --no-halt -- --app-id "YOUR_DISCORD_APP_ID" --log-level debug
```

### Testing

```sh
mix test
```

### Building

Build standalone binary:

```sh
MIX_ENV=prod mix release zdbeam
```

Binary output: `burrito_out/zdbeam_macos`

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

simulating checks: every 5s

time range: 17:54:52 → 22:47:45 (4h 52m)

final state: idling
state changes: 3

check 11: [18:00:03] L6000: idling → workout name="Active Recovery"
check 24: [19:58:26] L13800: workout name="Active Recovery" → free_ride route="Loopin Lava" world="Watopia"
check 25: [20:02:46] L14400: free_ride route="Loopin Lava" world="Watopia" → idling

events:
  [18:03:43] L6146: set_workout workout="Active Recovery"
  [18:03:44] L6160: setting_route route="Loopin Lava"
  [18:03:44] L6196: save_activity world="Watopia"
  ...
  [19:57:23] L13733: save_activity world="Watopia"
  [20:02:06] L14098: completed_workout
  [20:02:06] L14108: save_activity world="Watopia"
  [20:03:04] L14877: end_activity
  [20:03:04] L14879: save_activity world="Active Recovery on Loopin Lava in Watopia"
```

### Project Structure

```
lib/
├── zdbeam.ex                   # Public API module
└── zdbeam/
    ├── activity_formatter.ex   # Activity data formatting
    ├── application.ex          # OTP Application supervisor & CLI
    ├── discord_rpc.ex          # Discord RPC client (GenServer)
    ├── log_simulator.ex        # Log parsing simulator for debugging
    ├── zwift_log_parser.ex     # Log file parser
    ├── zwift_log_patterns.ex   # Log pattern matching rules
    └── zwift_mon.ex            # Zwift activity monitor (GenServer)
```

## License

MIT License. See [LICENSE](LICENSE) for details.

Images in `assets/` are from [Zwift media kits](https://news.zwift.com/en-WW/assets/227831/) and used to display Zwift branding in Discord Rich Presence.

## AI Usage Disclaimer

Development in this repository makes heavy use of AI (mostly Claude Sonnet 4.5).
The resulting code is manually reviewed, tested, and modified as needed by a human.
(I swear I'm not a robot, [proof of humanhood][not-a-robot] available upon request.)

[not-a-robot]: https://neal.fun/not-a-robot/
