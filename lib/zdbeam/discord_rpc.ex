defmodule Zdbeam.DiscordRPC do
  @moduledoc """
  Discord Rich Presence client using IPC (Inter-Process Communication).

  Connects to Discord client via Unix domain sockets (macOS/Linux) or named pipes (Windows)
  and updates Rich Presence status.

  ## Examples

      # Automatic connection on start
      {:ok, _pid} = Zdbeam.DiscordRPC.start_link([])

      # Update presence
      activity = %{
        details: "Volcano Circuit, Watopia",
        state: "Free Ride",
        start_time: System.system_time(:second),
        large_image: "world_watopia"
      }
      Zdbeam.DiscordRPC.update_presence(activity)

      # Clear presence
      Zdbeam.DiscordRPC.clear_presence()

  """

  use GenServer
  require Logger

  @ipc_pipes 0..9

  # Opcodes
  @opcode_handshake 0
  @opcode_frame 1
  @opcode_close 2

  defmodule State do
    defstruct [
      :socket,
      :application_id,
      :connected,
      :activity
    ]
  end

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Updates Discord Rich Presence with activity data.

  ## Examples

      activity = %{
        details: "FTP Test",
        state: "Workout",
        start_time: System.system_time(:second),
        large_image: "world_watopia",
        large_text: "Watopia"
      }
      Zdbeam.DiscordRPC.update_presence(activity)

  """
  def update_presence(activity) do
    GenServer.cast(__MODULE__, {:update_presence, activity})
  end

  @doc """
  Clears Discord Rich Presence.

  ## Examples

      Zdbeam.DiscordRPC.clear_presence()

  """
  def clear_presence do
    GenServer.cast(__MODULE__, :clear_presence)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    application_id = Application.get_env(:zdbeam, :discord_application_id)

    state = %State{
      socket: nil,
      application_id: application_id,
      connected: false,
      activity: nil
    }

    # Try to connect after initialization
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    with {:ok, socket} <- connect_to_discord(),
         :ok <- send_handshake(socket, state.application_id),
         {:ok, %{"cmd" => "DISPATCH", "evt" => "READY"}} <- receive_message(socket) do
      Logger.info("Discord RPC ready")
      new_state = %{state | socket: socket, connected: true}
      resend_stored_activity(new_state)
    else
      {:error, reason} ->
        log_connection_error(reason)
        schedule_reconnect()
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:reconnect, %{socket: nil} = state) do
    send(self(), :connect)
    {:noreply, %{state | socket: nil, connected: false}}
  end

  def handle_info(:reconnect, %{socket: socket} = state) do
    :gen_tcp.close(socket)
    send(self(), :connect)
    {:noreply, %{state | socket: nil, connected: false}}
  end

  @impl true
  def handle_cast({:update_presence, activity}, %{connected: true} = state) do
    Logger.debug("sending presence: #{inspect(build_presence_payload(activity))}")
    do_send_presence(state, activity)
  end

  @impl true
  def handle_cast({:update_presence, activity}, state) do
    Logger.warning("presence update skipped: not connected")
    {:noreply, %{state | activity: activity}}
  end

  @impl true
  def handle_cast(:clear_presence, %{connected: true} = state) do
    do_send_presence(state, nil)
  end

  @impl true
  def handle_cast(:clear_presence, state) do
    {:noreply, %{state | activity: nil}}
  end

  @impl true
  def terminate(_reason, %{socket: socket, connected: true}) when not is_nil(socket) do
    send_close(socket)
    :gen_tcp.close(socket)
    :ok
  end

  def terminate(_reason, _state) do
    :ok
  end

  ## Private Functions

  defp connect_to_discord do
    # On macOS/Linux, Discord creates Unix domain sockets
    # On Windows, it uses named pipes \\.\pipe\discord-ipc-N

    case Burrito.Util.get_current_os() do
      :darwin -> connect_unix_socket()
      :linux -> connect_unix_socket()
      :windows -> connect_named_pipe()
    end
  end

  defp connect_unix_socket do
    @ipc_pipes
    |> Enum.flat_map(&socket_paths/1)
    |> Enum.find_value({:error, :not_found}, &try_connect_socket/1)
  end

  defp socket_paths(n) do
    [
      get_runtime_dir() <> "/discord-ipc-#{n}",
      "/tmp/discord-ipc-#{n}"
    ]
  end

  defp try_connect_socket(path) do
    with true <- File.exists?(path),
         {:ok, socket} <- :gen_tcp.connect({:local, path}, 0, [:binary, active: false], 1000) do
      {:ok, socket}
    else
      _ -> nil
    end
  end

  defp connect_named_pipe do
    # Windows named pipe connection would go here
    # For now, return error
    {:error, :not_implemented}
  end

  defp get_runtime_dir do
    System.get_env("XDG_RUNTIME_DIR") ||
      System.get_env("TMPDIR") ||
      System.get_env("TMP") ||
      System.get_env("TEMP") ||
      "/tmp"
  end

  defp send_handshake(socket, application_id) do
    payload = %{
      v: 1,
      client_id: application_id
    }

    send_message(socket, @opcode_handshake, payload)
  end

  defp send_frame(socket, payload) do
    send_message(socket, @opcode_frame, payload)
  end

  defp send_message(socket, opcode, payload) do
    json = Jason.encode!(payload)
    length = byte_size(json)

    # Message format: opcode (4 bytes little-endian) + length (4 bytes little-endian) + json
    header = <<opcode::little-32, length::little-32>>
    message = header <> json

    :gen_tcp.send(socket, message)
  end

  defp receive_message(socket) do
    with {:ok, <<opcode::little-32, length::little-32>>} <- :gen_tcp.recv(socket, 8, 5000),
         {:ok, data} <- :gen_tcp.recv(socket, length, 5000) do
      case opcode do
        @opcode_close ->
          Logger.info("connection closed by Discord")
          {:error, :connection_closed}

        _ ->
          Jason.decode(data)
      end
    end
  end

  defp send_close(socket) do
    payload = Jason.encode!(%{})
    message = <<@opcode_close::little-32, byte_size(payload)::little-32, payload::binary>>

    case :gen_tcp.send(socket, message) do
      :ok ->
        :ok

      error ->
        Logger.warning("close send failed: #{inspect(error)}")
        error
    end
  end

  defp build_presence_payload(nil) do
    build_activity_payload(nil)
  end

  defp build_presence_payload(activity) do
    activity_obj = %{
      details: activity.details,
      state: activity.state
    }

    activity_obj =
      if activity.start_time do
        Map.put(activity_obj, :timestamps, %{start: activity.start_time})
      else
        activity_obj
      end

    assets = %{}

    assets =
      if activity.large_image,
        do: Map.put(assets, :large_image, activity.large_image),
        else: assets

    assets =
      if activity.large_text, do: Map.put(assets, :large_text, activity.large_text), else: assets

    assets =
      if activity.small_image,
        do: Map.put(assets, :small_image, activity.small_image),
        else: assets

    assets =
      if activity.small_text, do: Map.put(assets, :small_text, activity.small_text), else: assets

    activity_obj =
      if map_size(assets) > 0 do
        Map.put(activity_obj, :assets, assets)
      else
        activity_obj
      end

    build_activity_payload(activity_obj)
  end

  defp build_activity_payload(activity_obj) do
    %{
      cmd: "SET_ACTIVITY",
      args: %{
        pid: :os.getpid() |> List.to_integer(),
        activity: activity_obj
      },
      nonce: generate_nonce()
    }
  end

  defp generate_nonce do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp schedule_reconnect do
    Process.send_after(self(), :reconnect, 5000)
  end

  defp log_connection_error(:not_found) do
    Logger.warning("connection failed: Discord not running, retrying in 5s")
  end

  defp log_connection_error(reason) do
    Logger.warning("connection failed: #{inspect(reason)}, retrying in 5s")
  end

  defp resend_stored_activity(%{activity: nil} = state) do
    {:noreply, state}
  end

  defp resend_stored_activity(%{activity: activity} = state) do
    do_send_presence(state, activity)
  end

  defp do_send_presence(state, activity) do
    payload = build_presence_payload(activity)

    with :ok <- send_frame(state.socket, payload),
         {:ok, response} <- receive_message(state.socket) do
      if is_nil(activity), do: Logger.info("presence cleared")
      Logger.debug("Discord response: #{inspect(response)}")
      {:noreply, %{state | activity: activity}}
    else
      {:error, reason} ->
        log_message = if activity, do: "presence send failed", else: "presence clear failed"
        Logger.error("#{log_message}: #{inspect(reason)}")
        schedule_reconnect()
        {:noreply, %{state | connected: false}}
    end
  end
end
