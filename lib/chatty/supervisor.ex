defmodule Chatty.Supervisor do
  use Supervisor

  alias Chatty.Env

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  ###

  def init([]) do
    connection_opts = [
      name: Chatty.Connection,
      host: Env.get(:host, "irc.freenode.net"),
      port: Env.get(:port, 6667),
      channels: Env.get(:channels, []),
      nickname: Env.get(:nickname, "chatty_bot"),
      password: Env.get(:password, nil),
    ]
    children = [
      worker(Chatty.Connection, [connection_opts]),
    ]
    supervise(children, strategy: :one_for_one)
  end
end
