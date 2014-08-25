defmodule Chatty.HookHelpers do
  @moduledoc false

  import Chatty.Logger, warn: false
  import Chatty.IRCHelpers, only: [irc_cmd: 3]

  require Record
  Record.defrecordp :hookrec, [
    type: nil, direct: false, exclusive: false, fn: nil, chan: nil
  ]

  def add_hook(hooks, id, f, opts) do
    hook = Enum.reduce(opts, hookrec(fn: f), fn
      {:in, type}, rec ->
        hookrec(rec, type: type)
      {:direct, flag}, rec ->
        hookrec(rec, direct: flag)
      {:exclusive, flag}, rec ->
        hookrec(rec, exclusive: flag)
      {:channel, chan}, rec ->
        hookrec(rec, chan: chan)
    end)
    hooks ++ [{id, hook}]
  end

  def remove_hook(hooks, id) do
    Keyword.delete(hooks, id)
  end


  def process_hooks({chan, sender, msg}, hooks, info, sock) do
    receiver = get_message_receiver(msg)

    Enum.reduce(hooks, 0, fn
      {_, hookrec(type: type, direct: direct, exclusive: ex, fn: f, chan: hook_chan)}, successes ->
				#log "testing hook: #{inspect f}"
        if hook_chan == nil or "\#"<>hook_chan == chan do
          if ((not direct) || (receiver == info.nickname)) && ((not ex) || (successes == 0)) do
            arg = case type do
              :text  -> if direct do strip_msg_receiver(msg, receiver) else msg end
              :token -> tokenize(msg)
            end

            #log "applying hook: #{inspect f}"
            if resolve_hook_result(f.(sender, arg), chan, info, sock) do
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

  defp resolve_hook_result(nil, _chan, _info, _sock) do
    nil
  end

  defp resolve_hook_result({:reply, text}, chan, info, sock) do
    irc_cmd(sock, "PRIVMSG", "#{chan} #{info.nickname}: :#{text}")
  end

  defp resolve_hook_result({:reply, to, text}, chan, _info, sock) do
    irc_cmd(sock, "PRIVMSG", "#{chan} :#{to}: #{text}")
  end

  defp resolve_hook_result({:msg, text}, chan, _info, sock) do
    irc_cmd(sock, "PRIVMSG", "#{chan} :#{text}")
  end

  defp resolve_hook_result({:notice, text}, chan, _info, sock) do
    irc_cmd(sock, "NOTICE", "#{chan} :#{text}")
  end

  defp resolve_hook_result(messages, chan, info, sock) when is_list(messages) do
    Enum.reduce(messages, nil, fn msg, status ->
      new_status = resolve_hook_result(msg, chan, info, sock)
      status || new_status
    end)
  end
end
