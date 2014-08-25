defmodule Chatty.IRCHelpers do
  @moduledoc false

  import Chatty.Logger

  def irc_cmd(sock, cmd, rest) do
    log "Executing command #{cmd} with args #{inspect rest}"
    :ok = :gen_tcp.send(sock, [cmd, " ", rest, "\r\n"])
    sock
  end

  def irc_identify(sock, nil) do
    sock
  end

  def irc_identify(sock, password) do
    irc_cmd(sock, "PRIVMSG", ["NickServ :identify ", password])
  end

  def irc_join(sock, list) do
    Enum.each(list, fn chan ->
      irc_cmd(sock, "JOIN", [?#, chan])
    end)
    sock
  end

  def translate_msg(msg) do
    {prefix, command, args} = parse_msg(msg)

    sender = if prefix do
      case Regex.run(~r"^([^! ]+)(?:$|!)", List.to_string(prefix)) do
        [_, sender] -> sender
        other -> log "bad sender: #{inspect prefix} #{inspect other}"; nil
      end
    end

    case command do
      'PRIVMSG' ->
        [chan, msg] = args
        {:privmsg, chan, sender, msg}
      '332' ->
        [_, chan, topic] = args
        {:topic, chan, topic}
      'PING' ->
        :ping
      _ -> nil
    end
  end

  defp parse_msg(":" <> rest) do
    {prefix, rest} = parse_until(rest, ?\s)
    {nil, cmd, args} = parse_msg(rest)
    {prefix, cmd, args}
  end

  defp parse_msg(msg) do
    {cmd, argstr} = parse_until(msg, ?\s)
    {nil, cmd, parse_args(argstr)}
  end


  defp parse_args(str), do: parse_args(str, [], [])

  defp parse_args(" " <> rest, [], acc) do
    parse_args(rest, [], acc)
  end

  defp parse_args(" " <> rest, arg, acc) do
    parse_args(rest, [], [List.to_string(Enum.reverse(arg))|acc])
  end

  defp parse_args(":" <> rest, [], acc) do
    Enum.reverse([rest|acc])
  end

  defp parse_args("", [], acc) do
    Enum.reverse(acc)
  end

  defp parse_args("", arg, acc) do
    Enum.reverse([List.to_string(Enum.reverse(arg))|acc])
  end

  defp parse_args(<<char::utf8, rest::binary>>, arg, acc) do
    parse_args(rest, [char|arg], acc)
  end


  defp parse_until(bin, char) do
    parse_until(bin, char, [])
  end

  defp parse_until(<<char::utf8>> <> rest, char, acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_until(<<char::utf8>> <> rest, mark, acc) do
    parse_until(rest, mark, [char|acc])
  end
end
