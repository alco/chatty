defmodule Chatty.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  ###

  def init([]) do
    children = [
      worker(Chatty.Conn, []),
    ]
    supervise(children, strategy: :one_for_one)
  end
end
