defmodule Chatty.HookHelpers do
  @moduledoc false

  require Logger
  import Chatty.IRCHelpers, only: [irc_cmd: 3]

  require Record
  Record.defrecordp :hookrec, [
    type: :text, direct: false, exclusive: false, fn: nil, chan: nil, public_only: true
  ]

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

  defp resolve_hook_result(messages, chan, sender, sock) when is_list(messages) do
    Enum.reduce(messages, nil, fn msg, status ->
      new_status = do_resolve_hook_result(split_text(msg), chan, sender, sock)
      status || new_status
    end)
  end

  defp resolve_hook_result(message, chan, sender, sock) do
    do_resolve_hook_result(split_text(message), chan, sender, sock)
  end

  # Reply to the person that we received the message from
  defp do_resolve_hook_result({:reply, lines}, chan, sender, sock) do
    {first_line, rest_lines} = Enum.split(lines, 1)
    irc_cmd(sock, "PRIVMSG", [response_prefix(:reply, chan, sender), first_line])
    send_lines("PRIVMSG", rest_lines, sock, chan)
  end

  # Reply to the indicated person
  defp do_resolve_hook_result({:reply, to, lines}, chan, _sender, sock) do
    {first_line, rest_lines} = Enum.split(lines, 1)
    irc_cmd(sock, "PRIVMSG", [response_prefix(:reply, chan, to), first_line])
    send_lines("PRIVMSG", rest_lines, sock, chan)
  end

  # Just send a message to the channel
  defp do_resolve_hook_result({:msg, lines}, chan, _sender, sock) do
    send_lines("PRIVMSG", lines, sock, chan)
  end

  # Send a notice to the channel
  defp do_resolve_hook_result({:notice, lines}, chan, _sender, sock) do
    send_lines("NOTICE", lines, sock, chan)
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

  defp send_lines(msg_type, lines, sock, chan) do
    Enum.each(lines, &irc_cmd(sock, msg_type, [response_prefix(:msg, chan), &1]))
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
