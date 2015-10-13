defmodule Chatty.Supervisor do
  use Supervisor

  alias Chatty.Env
  alias Chatty.Connection.UserInfo

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  ###

  def init([]) do
    user_info = %UserInfo{
      host: Env.get(:host, "irc.freenode.net") |> String.to_char_list,
      port: Env.get(:port, 6667),
      channels: Env.get(:channels, []),
      nickname: Env.get(:nickname, "chatty_bot"),
      password: Env.get(:password, nil),
    }
    children = [
      worker(GenEvent, [[name: Chatty.IRCEventManager]]),
      worker(Chatty.HookAgent, []),
      worker(Chatty.HookManager, [user_info]),
      supervisor(Task.Supervisor, [[name: Chatty.HookTaskSupervisor]]),
      worker(Chatty.Connection, [user_info]),
    ]
    supervise(children, strategy: :one_for_one)
  end
end
