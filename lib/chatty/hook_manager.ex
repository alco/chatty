defmodule Chatty.HookManager do
  use GenServer

  require Logger

  alias Chatty.Hook

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # TODO: consider replacing the anonymous function with a module and a behaviour
  def add_hook(id, f, options \\ []) do
    GenServer.call(__MODULE__, {:add_hook, id, f, options})
  end

  def remove_hook(id) do
    GenServer.call(__MODULE__, {:remove_hook, id})
  end

  def process_message(message) do
    GenServer.cast(__MODULE__, {:process_message, message})
  end

  ###

  def init([]) do
    GenEvent.add_handler(Chatty.IRCEventManager, Chatty.IRCHookHandler, __MODULE__)
    state = %{
      hooks: [],
    }
    {:ok, state}
  end

  def handle_cast({:process_message, message}, %{hooks: hooks} = state) do
    Logger.debug("HookManager: Handling #{inspect message}")
    case message do
      {:topic, _chan, _topic} ->
        nil
      {command, _chan, _sender} when command in [:join, :part] ->
        nil
      {:privmsg, chan, sender, message} ->
        # FIXME: update the architecture of message processing by hooks
        user_info = nil
        sock = nil
        Chatty.HookHelpers.process_hooks({chan, sender, message}, hooks, user_info, sock)
    end
    {:noreply, state}
  end

  def handle_call({:add_hook, id, f, options}, _from, state) do
    # TODO: handle id collisions
    hook = %Hook{id: id, fn: f}
    {response, updated_state} = case apply_hook_options(hook, options) do
      {:ok, hook} ->
        {:ok, Map.update!(state, :hooks, & &1 ++ [hook])}
      {:bad_option, _} = reason ->
        {{:error, reason}, state}
    end
    {:reply, response, updated_state}
  end

  def handle_call({:remove_hook, id}, _from, %{hooks: hooks} = state) do
    updated_state = Map.update!(state, :hooks, fn hooks ->
      Enum.reject(hooks, fn %Hook{id: hook_id} -> hook_id == id end)
    end)
    response = if hooks != updated_state.hooks do
      :ok
    else
      :not_found
    end
    {:reply, response, state}
  end

  ###

  defp apply_hook_options(hook, options) do
    {hook, bad_options} = Enum.reduce(options, {hook, []}, fn option, bad_options ->
      hook = case option do
        {:in, type}          -> %Hook{hook | type: type}
        {:channel, chan}     -> %Hook{hook | chan: chan}
        {:direct, flag}      -> %Hook{hook | direct: flag}
        {:exclusive, flag}   -> %Hook{hook | exclusive: flag}
        {:public_only, flag} -> %Hook{hook | public_only: flag}
        _ ->
          bad_options = [option | bad_options]
          hook
      end
      {hook, bad_options}
    end)
    if bad_options == [] do
      {:ok, hook}
    else
      {:bad_option, List.first(bad_options)}
    end
  end
end
