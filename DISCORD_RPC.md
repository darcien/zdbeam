# Discord RPC Protocol

Technical reference for Discord Rich Presence IPC implementation.

## Overview

Pure Elixir implementation of Discord IPC protocol. No C++ SDK required.

Discord's RPC protocol runs over IPC (Inter-Process Communication) using Unix domain sockets (macOS/Linux) or named pipes (Windows). The protocol uses a binary framing format with JSON payloads for commands and events.

## Connection Points

Discord listens on multiple IPC endpoints (tries 0-9):

**macOS/Linux:**
```
$XDG_RUNTIME_DIR/discord-ipc-0
$XDG_RUNTIME_DIR/discord-ipc-1
...
/tmp/discord-ipc-0
/tmp/discord-ipc-1
...
```

**Windows:**
```
\\.\pipe\discord-ipc-0
\\.\pipe\discord-ipc-1
...
```

### Message Format

All messages use a fixed 8-byte header followed by a JSON payload:

```
[opcode:32-little] [length:32-little] [json_payload]
```

- Opcode: 4 bytes, little-endian integer
- Length: 4 bytes, little-endian integer (payload size)
- Payload: N bytes, JSON string

### Opcodes

```elixir
@opcode_handshake 0  # Initial connection handshake
@opcode_frame     1  # Data frames (commands and events)
@opcode_close     2  # Close connection
@opcode_ping      3  # Ping (keepalive)
@opcode_pong      4  # Pong (response to ping)
```

### Message Flow

```
Client                    Discord
  |                            |
  |  1. Connect to socket      |
  |--------------------------->|
  |                            |
  |  2. HANDSHAKE (opcode 0)   |
  |--------------------------->|
  |     {v: 1, client_id}      |
  |                            |
  |  3. READY event (opcode 1) |
  |<---------------------------|
  |     {cmd: "DISPATCH",      |
  |      evt: "READY"}         |
  |                            |
  |  4. SET_ACTIVITY (opcode 1)|
  |--------------------------->|
  |     {cmd: "SET_ACTIVITY",  |
  |      args: {activity}}     |
  |                            |
  |  5. Response (opcode 1)    |
  |<---------------------------|
  |                            |
```

## Implementation

### Connection

Tries IPC endpoints 0-9 until connection succeeds.

### Handshake

```elixir
payload = %{
  v: 1,                    # Protocol version (always 1)
  client_id: "client_id"   # Discord Application ID (string)
}

send_message(socket, @opcode_handshake, payload)
```

Discord responds with READY event containing user info and configuration.

### Setting Activity

```elixir
payload = %{
  cmd: "SET_ACTIVITY",     # Command name
  args: %{
    pid: :os.getpid() |> List.to_integer(),  # PID as integer
    activity: %{
      details: "...",      # Top line: what player is doing
      state: "...",        # Bottom line: party status
      timestamps: %{
        start: 1234567890  # Unix timestamp (integer)
      },
      assets: %{
        large_image: "key",    # Asset key from Discord app
        large_text: "hover",   # Hover tooltip text
        small_image: "key",    # Small badge asset key
        small_text: "hover"    # Small badge tooltip
      }
    }
  },
  nonce: "unique-id"       # Request ID for response correlation
}

send_message(socket, @opcode_frame, payload)
```

See Discord Rich Presence documentation for complete activity schema.

### Message Encoding (`send_message/3`)

```elixir
defp send_message(socket, opcode, payload) do
  json = Jason.encode!(payload)
  length = byte_size(json)

  # Build binary message
  header = <<opcode::little-32, length::little-32>>
  message = header <> json

  :gen_tcp.send(socket, message)
end
```

### Message Decoding (`receive_message/1`)

```elixir
defp receive_message(socket) do
  # Read 8-byte header
  case :gen_tcp.recv(socket, 8, 5000) do
    {:ok, <<opcode::little-32, length::little-32>>} ->
      # Read payload
      case :gen_tcp.recv(socket, length, 5000) do
        {:ok, data} ->
          Jason.decode(data)
        error -> error
      end
    error -> error
  end
end
```

## Activity Schema

Required fields:
- `details`: string, top line text
- `state`: string, bottom line text

Optional fields:
- `timestamps.start`: integer, Unix timestamp
- `timestamps.end`: integer, Unix timestamp
- `assets.large_image`: string, asset key
- `assets.large_text`: string, hover text
- `assets.small_image`: string, asset key
- `assets.small_text`: string, hover text
- `party.id`: string, party identifier
- `party.size`: [current, max], array of two integers
- `buttons`: array of up to 2 button objects with `label` and `url`

Assets must be uploaded to the Discord application dashboard before use.

## Reconnection

Automatic reconnection on disconnect with 5 second delay.

## Socket Types

Unix domain sockets (macOS/Linux):
```elixir
:gen_tcp.connect({:local, path}, 0, [:binary, active: false], 1000)
```

Windows named pipes not implemented.

## Rate Limits

Discord rate limits: 5 updates per 20 seconds per user.

## References

- [Discord RPC Specification](https://github.com/discord/discord-rpc/blob/master/documentation/hard-mode.md)
- [Discord Rich Presence Documentation](https://discord.com/developers/docs/rich-presence/how-to)
- [Erlang gen_tcp Documentation](https://www.erlang.org/doc/man/gen_tcp.html)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
