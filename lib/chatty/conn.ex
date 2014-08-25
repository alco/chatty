defmodule Chatty.Conn do
  @moduledoc false

  alias Chatty.ConnServer

  def start_link() do
    ConnServer.start_link(__MODULE__, [], [
      name: __MODULE__,
      host: get_env(:host, "irc.freenode.net"),
      port: get_env(:port, 6667),
      channels: get_env(:channels, []),
      nickname: get_env(:nickname, "chatty_bot"),
      password: get_env(:password, nil),
    ])
  end

  def init([]) do
    {:ok, nil}
  end

  defp get_env(key, default) do
    case Application.fetch_env(:chatty, key) do
      {:ok, value} -> value
      :error -> default
    end
  end
end

