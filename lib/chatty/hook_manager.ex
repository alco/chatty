defmodule Chatty.HookManager do
  use GenServer

  require Logger

  alias Chatty.Hook
  alias Chatty.HookAgent
  alias Chatty.HookTaskSupervisor

  import Chatty.IRCHelpers, only: [irc_cmd: 3]

  @default_task_timeout 2000

  def start_link(user_info) do
    GenServer.start_link(__MODULE__, [user_info], name: __MODULE__)
  end

  # TODO: consider replacing the anonymous function with a module and a behaviour
  def add_hook(kind, id, f, options \\ []) do
    GenServer.call(__MODULE__, {:add_hook, kind, id, f, options})
  end

  def remove_hook(id) do
    GenServer.call(__MODULE__, {:remove_hook, id})
  end

  def process_message({message, sock}) do
    GenServer.cast(__MODULE__, {:process_message, message, sock})
  end

  ###

  def init([user_info]) do
    GenEvent.add_handler(Chatty.IRCEventManager, Chatty.IRCHookHandler, __MODULE__)
    hooks = HookAgent.get_all_hooks
    state = %{
      user_info: user_info,
      hooks: hooks,
    }
    {:ok, state}
  end

  def handle_cast({:process_message, _, _}, %{hooks: hooks} = state) when hooks == %{} do
    {:noreply, state}
  end

  def handle_cast(
    {:process_message, {message_kind, message_args} = message, sock},
    %{user_info: user_info, hooks: hooks} = state)
  do
    Logger.debug(["HookManager: Handling ", inspect(message)])
    hooks_to_invoke = filter_applicable_hooks(hooks, message_kind)
    max_hook_timeout = max_hook_timeout(hooks_to_invoke)
    hooks_to_tasks(message_kind, message_args, hooks_to_invoke, user_info)
    |> process_tasks(max_hook_timeout, sock)
    {:noreply, state}
  end

  def handle_call({:add_hook, kind, id, f, options}, _from, state) do
    if valid_hook_kind?(kind) do
      hook = %Hook{
        id: id, fn: f, kind: kind,
        task_timeout: Chatty.Env.get(:hook_task_timeout, @default_task_timeout)
      }
      {response, updated_state} = case apply_hook_options(hook, options) do
        {:ok, hook} ->
          case HookAgent.put_hook(id, hook) do
            :ok ->
              {:ok, Map.update!(state, :hooks, &Map.put(&1, id, hook))}
            :id_collision ->
              {{:error, :hook_id_already_used}, state}
          end
        {:bad_option, _} = reason ->
          {{:error, reason}, state}
      end
      {:reply, response, updated_state}
    else
    end
  end

  def handle_call({:remove_hook, id}, _from, %{hooks: hooks} = state) do
    updated_state = Map.update!(state, :hooks, &Map.delete(&1, id))
    response = if hooks != updated_state.hooks do
      :ok = HookAgent.delete_hook(id)
      :ok
    else
      :not_found
    end
    {:reply, response, updated_state}
  end

  def handle_info({:hook_task_result, ref, result}, state) do
    Logger.debug("Got unprocessed task result with ref #{inspect ref}: #{inspect result}")
    {:noreply, state}
  end

  ###

  defp valid_hook_kind?(kind) do
    kind in [:privmsg, :topic, :presence]
  end

  defp apply_hook_options(hook, options) do
    {hook, bad_options} = Enum.reduce(options, {hook, []}, fn option, {hook, bad_options} ->
      hook = case option do
        {:in, type} when is_atom(type) ->
          %Hook{hook | type: type}
        {:channel, chan} when is_binary(chan) ->
          %Hook{hook | chan: chan}
        {:direct, flag} when is_boolean(flag) ->
          %Hook{hook | direct: flag}
        {:exclusive, flag} when is_boolean(flag) ->
          %Hook{hook | exclusive: flag}
        {:public_only, flag} when is_boolean(flag) ->
          %Hook{hook | public_only: flag}
        {:task_timeout, timeout} when is_integer(timeout) and timeout > 0 ->
          %Hook{hook | task_timeout: timeout}
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

  defp filter_applicable_hooks(hooks, message_kind) do
    applicable_hook_kind = applicable_hook_kind(message_kind)
    hooks
    |> Enum.map(fn {_, hook} -> hook end)
    |> Enum.filter(fn %Hook{kind: hook_kind} -> hook_kind == applicable_hook_kind end)
  end

  defp hooks_to_tasks(:privmsg, [chan, sender, message], hooks, user_info) do
    receiver = get_message_receiver(message)
    hooks
    |> Enum.filter(&hook_applicable_on_chan?(&1, chan))
    |> Enum.filter(&hook_applicable_to_receiver?(&1, receiver, user_info.nickname))
    |> Enum.map(&{&1, response_chan_for_hook(&1, chan, sender, user_info.nickname)})
    |> Enum.reject(fn {_hook, response_chan} -> is_nil(response_chan) end)
    |> Enum.map(fn {hook, response_chan} ->
      args = build_privmsg_args(hook, message, sender, receiver)
      hook_to_task(hook, response_chan, sender, args)
    end)
  end

  defp hooks_to_tasks(action, [chan, sender], hooks, user_info) when action in [:join, :part] do
    response_chan = resolve_response_channel(chan, user_info.nickname, sender)
    hooks
    |> Enum.filter(&hook_applicable_on_chan?(&1, chan))
    |> Enum.map(&hook_to_task(&1, response_chan, sender, [chan, action, sender]))
  end

  defp hooks_to_tasks(:topic_change, [chan, sender, _topic] = args, hooks, user_info) do
    # TODO: extract chan and sender to be common for all hook types
    response_chan = resolve_response_channel(chan, user_info.nickname, sender)
    hooks
    |> Enum.filter(&hook_applicable_on_chan?(&1, chan))
    |> Enum.map(&hook_to_task(&1, response_chan, nil, args))
  end

  defp process_tasks(hook_tasks, max_task_timeout, sock) do
    hook_tasks
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
    |> collect_tasks(max_task_timeout)
    |> send_responses(sock)
  end

  defp build_privmsg_args(hook, message, sender, receiver) do
    message_sans_receiver = strip_message_receiver(hook.direct, message, receiver)
    input = case hook.type do
      :text -> message_sans_receiver
      :token -> tokenize(message_sans_receiver)
    end
    [sender, input]
  end

  defp hook_to_task(hook, response_chan, sender, args) do
    # TODO: test resilience to crashes in tasks
    parent = self()
    ref = make_ref()
    {:ok, task} = Task.Supervisor.start_child(HookTaskSupervisor, fn ->
      :random.seed(:erlang.monotonic_time)
      result = resolve_hook_result(apply(hook.fn, args), response_chan, sender)
      send(parent, {:hook_task_result, ref, result})
    end)
    {ref, {hook, task}}
  end

  defp applicable_hook_kind(:topic_change), do: :topic
  defp applicable_hook_kind(:privmsg), do: :privmsg
  defp applicable_hook_kind(presence) when presence in [:join, :part], do: :presence

  defp hook_applicable_on_chan?(hook, chan) do
    is_nil(hook.chan) or ("#" <> hook.chan == chan)
  end

  defp hook_applicable_to_receiver?(hook, receiver, user_nickname) do
    hook.kind != :privmsg or (not hook.direct) or (receiver == user_nickname)
  end

  defp response_chan_for_hook(hook, chan, sender, user_nickname) do
    case {resolve_response_channel(chan, user_nickname, sender), hook.public_only} do
      {{:private, _}, true} -> nil
      {chan, _} -> chan
    end
  end

  defp collect_tasks(hook_tasks, max_task_timeout) do
    collect_tasks(hook_tasks, max_task_timeout, :erlang.monotonic_time, [])
  end

  defp collect_tasks(hook_tasks, _, _, results) when hook_tasks == %{} do
    results
  end

  defp collect_tasks(hook_tasks, max_task_timeout, timestamp, results) do
    # TODO: kill overtime tasks and make sure we don't get results from tasks spawned during
    # previous invocations of process_message()
    receive do
      {:hook_task_result, ref, result} ->
        new_timestamp = :erlang.monotonic_time
        elapsed_milliseconds =
          :erlang.convert_time_unit(new_timestamp - timestamp, :native, :milli_seconds)
        remaining_timeout = max(0, max_task_timeout - elapsed_milliseconds)

        {{hook, _}, remaining_hook_tasks} = Map.pop(hook_tasks, ref)
        updated_results = if result != [] do
          [{hook, result} | results]
        else
          results
        end

        collect_tasks(remaining_hook_tasks, remaining_timeout, new_timestamp, updated_results)

      after max_task_timeout ->
        results
    end
  end

  defp get_message_receiver(msg) do
    case Regex.run(~r"^([-_^[:alnum:]]+)(?::)", msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp tokenize(msg),
    do: String.split(msg, ~r"[[:space:]]")

  defp strip_message_receiver(false, message, _) do
    message
  end

  defp strip_message_receiver(true, message, receiver) do
    message
    |> String.slice(byte_size(receiver), byte_size(message))
    |> String.lstrip(?:)
    |> String.strip()
  end

  defp resolve_hook_result(nil, _chan, _sender),
    do: []

  defp resolve_hook_result(messages, chan, sender) when is_list(messages),
    do: Enum.flat_map(messages, &do_resolve_hook_result(split_text(&1), chan, sender))

  defp resolve_hook_result(message, chan, sender),
    do: do_resolve_hook_result(split_text(message), chan, sender)

  # Reply to the person that we received the message from
  defp do_resolve_hook_result({:reply, lines}, chan, sender) do
    {first_line, rest_lines} = Enum.split(lines, 1)
    [
      {"PRIVMSG", [response_prefix(:reply, chan, sender), first_line]}
      |
      prepare_lines("PRIVMSG", rest_lines, chan)
    ]
  end

  # Reply to the indicated person
  defp do_resolve_hook_result({:reply, to, lines}, chan, _sender) do
    {first_line, rest_lines} = Enum.split(lines, 1)
    [
      {"PRIVMSG", [response_prefix(:reply, chan, to), first_line]}
      |
      prepare_lines("PRIVMSG", rest_lines, chan)
    ]
  end

  # Just send a message to the channel
  defp do_resolve_hook_result({:msg, lines}, chan, _sender) do
    prepare_lines("PRIVMSG", lines, chan)
  end

  # Send a notice to the channel
  defp do_resolve_hook_result({:notice, lines}, chan, _sender) do
    prepare_lines("NOTICE", lines, chan)
  end

  defp split_text({:reply, text}),
    do: {:reply, split_lines(text)}

  defp split_text({:reply, to, text}),
    do: {:reply, to, split_lines(text)}

  defp split_text({:msg, text}),
    do: {:msg, split_lines(text)}

  defp split_text({:notice, text}),
    do: {:notice, split_lines(text)}

  defp split_lines(text) do
    text
    |> String.rstrip
    |> String.split("\n")
    |> Enum.drop_while(&String.strip(&1) == "")
  end

  defp prepare_lines(msg_type, lines, chan),
    do: Enum.map(lines, &{msg_type, [response_prefix(:msg, chan), &1]})

  # This is a private message, use the sender's name as the channel for the response
  defp resolve_response_channel(nickname, nickname, sender),
    do: {:private, sender}

  defp resolve_response_channel(chan, _, _),
    do: {:public, chan}

  defp response_prefix(:msg, {_, chan}),
    do: "#{chan} :"

  defp response_prefix(:reply, {:private, sender}, sender),
    do: "#{sender} :"

  defp response_prefix(:reply, {_, chan}, sender),
    do: "#{chan} :#{sender}: "


  defp send_responses(responses, sock) do
    Enum.map(responses, fn
      {%Hook{exclusive: true}, response} ->
        if match?([_], responses) do
          # Only send exclusive replies if no other hook matched the message
          send_response(response, sock)
        end
      {_, response} ->
        send_response(response, sock)
    end)
  end

  defp send_response(response, sock),
    do: Enum.each(response, fn {msg_type, payload} -> irc_cmd(sock, msg_type, payload) end)

  defp max_hook_timeout(hooks) do
    hooks
    |> Enum.map(fn %Hook{task_timeout: timeout} -> timeout end)
    |> Enum.max
  end
end
