defmodule Chatty.Conn do
  @moduledoc false

  alias Chatty.ConnServer

  def start_link() do
    ConnServer.start_link(__MODULE__, [], [
      name: __MODULE__,
      host: Application.get_env(:chatty, :host),
      port: Application.get_env(:chatty, :port),
      channels: Application.get_env(:chatty, :channels),
      nickname: Application.get_env(:chatty, :nickname),
      password: Application.get_env(:chatty, :password),
    ])
  end

  def init([]) do
    {:ok, nil}
  end
end

