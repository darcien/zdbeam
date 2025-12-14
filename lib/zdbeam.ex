defmodule Zdbeam do
  @moduledoc """
  Discord Rich Presence integration for Zwift.
  """

  @doc """
  Returns the current status of Zwift monitoring and Discord connection.

  ## Examples

      iex> Zdbeam.status()
      %{
        zwift: %{zwift_running: true, current_activity: %{...}},
        discord: %{connected: true}
      }

  """
  def status do
    zwift_status = Zdbeam.ZwiftReader.get_status()

    %{
      zwift: zwift_status,
      discord: %{
        connected: Process.whereis(Zdbeam.DiscordRPC) != nil
      }
    }
  end
end
