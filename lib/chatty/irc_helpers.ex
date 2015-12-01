defmodule Chatty.IRCHelpers do
  @moduledoc false

  require Logger

  def irc_cmd(sock, cmd, rest) do
    Logger.info(["Executing command #{cmd} with args ", inspect(rest)])
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
        other ->
          Logger.info(["bad sender: ", inspect(prefix), " ", inspect(other)])
          nil
      end
    end

    case command do
      'PRIVMSG' ->
        [chan, msg] = args
        {:privmsg, [msg, sender, chan]}
      '332' ->
        # Initial topic message that we get upon joining a channel
        [_, chan, topic] = args
        {:channel_topic, [topic, chan]}
      'TOPIC' ->
        # A topic change while we're inside a channel
        [chan, topic] = args
        {:topic_change, [topic, sender, chan]}
      'PING' ->
        :ping
      'JOIN' ->
        [chan | _] = args
        {:join, [sender, chan]}
      'PART' ->
        [chan | _] = args
        {:part, [sender, chan]}
      other ->
        Logger.warn(["Unhandled IRC message: ", inspect(other)])
        {:error, :unsupported}
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
