# Agents

## Programming Style

- Write clean, idiomatic Elixir code
- Never create new docs unless necessary - update existing ones only when code changes require it
- Never add comments explaining what code does (only why, when truly necessary)
- Be direct and concise in responses:
  - No emoji in technical explanations
  - State facts, show results, move on

## Code Output Style

**CLI output and logs** (UNIX-like: brief, precise, actionable):
- Logs: `activity changed: workout → free_ride`, not "The activity has been successfully changed from workout mode to free ride mode"
- Errors: `file not found: ~/Log.txt`, not "Error: We couldn't find the file at ~/Log.txt"
- Status: `final state: Idling`, not "The final state is: Idling"

**Documentation** (Elixir conventions):
- Module docs: brief description, then examples
- Function docs: describe behavior, return values, then examples
- Use proper Markdown formatting and code blocks

## Project Context

Discord Rich Presence for Zwift. Pure Elixir implementation, standalone binaries via Burrito.

**Stack**: Elixir 1.19.2+, OTP 28.2+, Burrito packaging

**Key modules**:
- `Zdbeam` - Public API module
- `Zdbeam.ActivityFormatter` - Format activity data for Discord
- `Zdbeam.Application` - OTP supervisor & CLI
- `Zdbeam.DiscordRPC` - Discord RPC client (GenServer)
- `Zdbeam.LogSimulator` - Log parsing simulator for debugging
- `Zdbeam.ZwiftLogParser` - Log file parser
- `Zdbeam.ZwiftLogPatterns` - Log pattern matching rules
- `Zdbeam.ZwiftMon` - Zwift activity monitor (GenServer)

**Configuration**: CLI args, not env vars. Required: `--app-id`, optional: `--check-interval`, `--log-level`

## Code Style

Follow standard Elixir conventions:

```elixir
# Use `with` for error handling
def update_discord_presence(activity) do
  with {:ok, socket} <- connect(),
       :ok <- send_update(socket, activity) do
    {:ok, socket}
  end
end

# Use pipe for data transformations
def process_lines(content) do
  content
  |> String.split("\n")
  |> Enum.filter(&valid?/1)
  |> Enum.map(&parse/1)
end

# Pattern matching in function heads
def format_activity(nil), do: {"Idling", nil}
def format_activity(%{type: :workout, workout_name: name}), do: {name, "Workout"}

# Tagged tuples for errors
{:ok, result} | {:error, reason}
```
