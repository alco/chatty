defmodule Chatty.Application do
  @moduledoc false

  use Application

  def start(_, _) do
    import Supervisor.Spec
    children = [worker(Chatty.Conn, [])]
    opts = [strategy: :one_for_one, name: Chatty.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

