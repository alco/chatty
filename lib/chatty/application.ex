defmodule Chatty.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    Chatty.Supervisor.start_link
  end
end
