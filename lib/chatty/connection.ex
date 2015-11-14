defmodule Chatty.Connection do
  use GenServer

  require Logger
  import Chatty.IRCHelpers

  alias Chatty.Connection.UserInfo

  @sleep_sec 10
  @ping_sec 5 * 60
  @max_attempts 30
  @ssl Application.get_env(:chatty, :ssl)

  def start_link(user_info) do
    GenServer.start_link(__MODULE__, [user_info], name: __MODULE__)
  end

  def send_message(chan, msg) do
    GenServer.cast(__MODULE__, {:send_message, chan, msg})
  end

  ###

  def init([user_info]) do
    # Perform an asynchronous connection attempt. The Chatty.Connection process should not be
    # blocked internally and should keep going between TCP disconnects and reconnects.
    send(self(), :connect)
    state = %{
      user_info: user_info,
      sock: nil,
      last_message_time: nil,
      channel_topics: %{},
    }
    {:ok, state}
  end

  def handle_cast({:send_message, chan, msg}, %{sock: sock} = state) do
    irc_cmd(sock, "PRIVMSG", "#{chan} :#{msg}")
    {:noreply, state}
  end

  def handle_info(:connect, state) do
    handle_info({:connect, 0}, state)
  end

  def handle_info({:connect, attempt_number}, %{user_info: user_info} = state) do
    case connect(user_info) do
      {:ok, sock} ->
        Logger.info("Did connect. Performing IRC handshake")
        sock = irc_handshake(sock, user_info)
        send_idle_timeout_guard()
        {:noreply, %{state | sock: sock, last_message_time: current_time()}}
      {:error, reason} ->
        Logger.warn("Failed to connect: #{inspect reason}.")
        if attempt_number < @max_attempts do
          # Try one more time after a while
          reconnect_after(@sleep_sec, attempt_number + 1)
          {:noreply, state}
        else
          # This is useless. Shut us down.
          Logger.error("Failed to connect repeatedly, shutting down.")
          {:stop, {:error, :failed_to_connect_repeatedly}, state}
        end
    end
  end

  def handle_info(:check_idle_time, %{last_message_time: nil} = state) do
    # We're in some transitionary state, don't do any idle checks for now.
    {:noreply, state}
  end

  def handle_info(:check_idle_time, %{sock: sock, last_message_time: time} = state) do
    updated_state = if time_diff(time) >= @ping_sec do
      # Something may have gone awry. Try reconnecting.
      :gen_tcp.close(sock)
      send(self(), :connect)
      %{state | sock: nil, last_message_time: nil}
    else
      # Check back again in the future.
      send_idle_timeout_guard()
      state
    end
    {:noreply, updated_state}
  end

  def handle_info({:tcp, sock, raw_msg}, %{sock: sock, user_info: user_info} = state) do
    msg = IO.iodata_to_binary(raw_msg) |> String.strip
    Logger.debug(["TCP message: ", msg])

    updated_state = case translate_msg(msg) do
      {:error, :unsupported} ->
        Logger.debug(["Ignoring unsupported message: ", msg])
        state
      :ping ->
        irc_cmd(sock, "PONG", user_info.nickname)
        state
      {:channel_topic, [topic, chan]} ->
        Map.update!(state, :channel_topics, &Map.put(&1, chan, topic))
      {:topic_change, [topic, _sender, chan]} = message ->
        Map.update!(state, :channel_topics, &Map.put(&1, chan, topic))
        GenEvent.notify(Chatty.IRCEventManager, {message, sock})
        state
      message ->
        GenEvent.notify(Chatty.IRCEventManager, {message, sock})
        state
    end
    {:noreply, %{updated_state | last_message_time: current_time()}}
  end

  def handle_info({:ssl, sock, raw_msg}, %{sock: sock, user_info: user_info} = state) do
    msg = IO.iodata_to_binary(raw_msg) |> String.strip
    Logger.debug(["TCP message: ", msg])

    updated_state = case translate_msg(msg) do
      {:error, :unsupported} ->
        Logger.debug(["Ignoring unsupported message: ", msg])
        state
      :ping ->
        irc_cmd(sock, "PONG", user_info.nickname)
        state
      {:channel_topic, [topic, chan]} ->
        Map.update!(state, :channel_topics, &Map.put(&1, chan, topic))
      {:topic_change, [topic, _sender, chan]} = message ->
        Map.update!(state, :channel_topics, &Map.put(&1, chan, topic))
        GenEvent.notify(Chatty.IRCEventManager, {message, sock})
        state
      message ->
        GenEvent.notify(Chatty.IRCEventManager, {message, sock})
        state
    end
    {:noreply, %{updated_state | last_message_time: current_time()}}
  end

  ## TCP
  def handle_info({:tcp_closed, sock}, %{sock: sock} = state) do
    Logger.warn("TCP socket closed.")
    reconnect_after(@sleep_sec)
    {:noreply, %{state | sock: nil, last_message_time: nil}}
  end

  def handle_info({:tcp_error, sock, reason}, %{sock: sock} = state) do
    Logger.error("TCP socket error: #{inspect reason}.")
    :gen_tcp.close(sock)
    reconnect_after(@sleep_sec)
    {:noreply, %{state | sock: nil, last_message_time: nil}}
  end

  ## SSL
  def handle_info({:ssl_closed, _}, state) do
    Logger.warn("SSL socket closed.")
    reconnect_after(@sleep_sec)
    {:noreply, %{state | sock: nil, last_message_time: nil}}
  end

  def handle_info({:ssl_error, sock, reason}, %{sock: sock} = state) do
    Logger.debug("SSL socket error: #{reason}")
    :ssl.close(sock)
    reconnect_after(@sleep_sec)
    {:noreply, %{state | sock: nil, last_message_time: nil}}
  end

  ###

  defp connect(%UserInfo{host: host, port: port}) do
<<<<<<< HEAD
    if @ssl do
      {:ok, socket} = :ssl.connect(host, port, packet: :line, active: true)
      :ssl.ssl_accept(socket)
      {:ok, socket}
    else
      :gen_tcp.connect(host, port, packet: :line, active: true)
    end
  end

  defp irc_handshake(sock, %UserInfo{nickname: nickname, password: password, channels: channels}) do
    sock
    |> irc_cmd("PASS", "*")
    |> irc_cmd("NICK", nickname)
    |> irc_cmd("USER", "#{nickname} 0 * :BEAM")
    |> irc_identify(password)
    |> irc_join(channels)
  end

  defp send_idle_timeout_guard() do
    Process.send_after(self(), :check_idle_time, @ping_sec * 1000)
  end

  ###

  defp reconnect_after(seconds, attempt_number \\ 0) do
    Logger.info("Retrying connect in #{seconds} seconds.")
    Process.send_after(self(), {:connect, attempt_number}, seconds * 1000)
  end

  defp current_time do
    :erlang.monotonic_time
  end

  defp time_diff(time) do
    :erlang.convert_time_unit(current_time() - time, :native, :seconds)
  end
end
