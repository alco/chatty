defmodule Chatty.HookHelpers do
  @moduledoc false

  import Chatty.Logger, warn: false
  import Chatty.IRCHelpers, only: [irc_cmd: 3]

  require Record
  Record.defrecordp :hookrec, [
    type: :text, direct: false, exclusive: false, fn: nil, chan: nil, public_only: true
  ]

  def add_hook(hooks, id, f, opts) do
    hook = Enum.reduce(opts, hookrec(fn: f), fn
      {:in, type}, rec ->
        hookrec(rec, type: type)
      {:channel, chan}, rec ->
        hookrec(rec, chan: chan)
      {:direct, flag}, rec ->
        hookrec(rec, direct: flag)
      {:exclusive, flag}, rec ->
        hookrec(rec, exclusive: flag)
      {:public_only, flag}, rec ->
        hookrec(rec, public_only: flag)
    end)
    hooks ++ [{id, hook}]
  end

  def remove_hook(hooks, id) do
    Keyword.delete(hooks, id)
  end


  def process_hooks({chan, sender, msg}, hooks, info, sock) do
    receiver = get_message_receiver(msg)

    Enum.reduce(hooks, 0, fn
      {_, hookrec(type: type, direct: direct, exclusive: ex, fn: f, chan: hook_chan)=rec},
      successes ->
				#log "testing hook: #{inspect f}"
        if hook_chan == nil or "\#"<>hook_chan == chan do
          if ((not direct) || (receiver == info.nickname)) && ((not ex) || (successes == 0)) do
            arg = case type do
              :text  -> if direct do strip_msg_receiver(msg, receiver) else msg end
              :token -> tokenize(msg)
            end

            #log "applying hook: #{inspect f}"
            public_only = hookrec(rec, :public_only)
            response_chan =
              case {resolve_response_channel(chan, info.nickname, sender), public_only} do
                {{:private, _}, true} -> nil
                {chan, _} -> chan
              end
            if response_chan && resolve_hook_result(f.(sender, arg), response_chan, sender, sock) do
              successes+1
            else
              successes
            end
          else
            #log "skipping hook: #{inspect f}"
            successes
          end
        else
          successes
        end
    end)
  end

  defp get_message_receiver(msg) do
    case Regex.run(~r"^([-_^[:alnum:]]+)(?::)", msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp tokenize(msg) do
    String.split(msg, ~r"[[:space:]]")
  end

  defp strip_msg_receiver(msg, receiver) do
    msg
    |> String.slice(byte_size(receiver), byte_size(msg))
    |> String.lstrip(?:)
    |> String.strip()
  end

  defp resolve_hook_result(nil, _chan, _sender, _sock) do
    nil
  end

  # Reply to the person that we received the message from
  defp resolve_hook_result({:reply, text}, chan, sender, sock) do
    irc_cmd(sock, "PRIVMSG", [response_prefix(:reply, chan, sender), text])
  end

  # Reply to the indicated person
  defp resolve_hook_result({:reply, to, text}, chan, _sender, sock) do
    irc_cmd(sock, "PRIVMSG", [response_prefix(:reply, chan, to), text])
  end

  # Just send a message to the channel
  defp resolve_hook_result({:msg, text}, chan, _sender, sock) do
    irc_cmd(sock, "PRIVMSG", [response_prefix(:msg, chan), text])
  end

  # Send a notice to the channel
  defp resolve_hook_result({:notice, text}, chan, _sender, sock) do
    irc_cmd(sock, "NOTICE", [response_prefix(:msg, chan), text])
  end

  defp resolve_hook_result(messages, chan, sender, sock) when is_list(messages) do
    Enum.reduce(messages, nil, fn msg, status ->
      new_status = resolve_hook_result(msg, chan, sender, sock)
      status || new_status
    end)
  end

  # This is a private message, use the sender's name as the channel for the response
  defp resolve_response_channel(nickname, nickname, sender) do
    {:private, sender}
  end

  defp resolve_response_channel(chan, _, _) do
    {:public, chan}
  end

  defp response_prefix(:msg, {_, chan}) do
    "#{chan} :"
  end

  defp response_prefix(:reply, {:private, sender}, sender) do
    "#{sender} :"
  end

  defp response_prefix(:reply, {_, chan}, sender) do
    "#{chan} :#{sender}: "
  end
end
