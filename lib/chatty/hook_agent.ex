defmodule Chatty.HookAgent do
  @moduledoc """
  A dumb agent for storing hooks. `Chatty.HookManager` relies on it for setting up its initial
  state. Added as a protection against losing hooks in case of a hook manager's crash.
  """

  def start_link do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def put_hook(id, %Chatty.Hook{} = hook) when is_atom(id) do
    Agent.update(__MODULE__, &Map.put(&1, id, hook))
  end

  def get_all_hooks do
    Agent.get(__MODULE__, & &1)
  end

  def delete_hook(id) do
    Agent.update(__MODULE__, &Map.delete(&1, id))
  end
end
