defmodule Chatty.ConnServer do
  @moduledoc false

  require Logger
  import Chatty.IRCHelpers

  alias Chatty.ConnServer.State
  alias Chatty.ConnServer.UserInfo
  alias Chatty.HookHelpers

  defp get_non_nil(keyword, key) do
    case Keyword.fetch!(keyword, key) do
      nil -> raise "Got nil for key #{inspect key}"
      other -> other
    end
  end

  def start_link(module, args, options \\ []) do
    host = Keyword.fetch!(options, :host) |> String.to_char_list
    port = Keyword.fetch!(options, :port)
    info = %UserInfo{
      host: host,
      port: port,
      nickname: get_non_nil(options, :nickname),
      password: Keyword.get(options, :password),
      channels: get_non_nil(options, :channels),
    }

    parent = self()
    ref = make_ref()
    server_pid = spawn_link(fn ->
      {status, state} = case module.init(args) do
        {:ok, state} -> {:ok, state}
        other -> {{:error, other}, nil}
      end
      send(parent, {ref, status})
      if status == :ok do
        connect(%State{}, {module, state, info})
      end
    end)
    receive do
      {^ref, :ok} -> :ok
      {^ref, {:error, reason}} -> exit(reason)
    end

    if name=options[:name] do
      Process.register(server_pid, name)
    end
    {:ok, server_pid}
  end

  def call(server, msg) do
    ref = make_ref()
    send(server, {__MODULE__, :call, {self(), ref}, msg})
    receive do
      {:reply, ^ref, reply} -> reply
    end
  end

  def cast(server, msg) do
    send(server, {__MODULE__, :cast, msg})
  end


  def add_hook(server, id, f, opts) do
    send(server, {__MODULE__, :internal, {:add_hook, id, f, opts}})
    :ok
  end

  def remove_hook(server, id) do
    send(server, {__MODULE__, :internal, {:remove_hook, id}})
    :ok
  end

  def send_message(server, chan, msg) do
    send(server, {__MODULE__, :internal, {:send_message, chan, msg}})
    :ok
  end


  @sleep_sec 10
  @ping_sec 5 * 60
  @maxattempts 30

  defp connect(server_state, user_state={_, _, %UserInfo{host: host, port: port}}) do
    case :gen_tcp.connect(host, port, packet: :line, active: true) do
      {:ok, sock} ->
        Process.delete(:connect_attempts)
        handshake(sock, server_state, user_state)

      other ->
        Logger.warn("Failed to connect: #{inspect other}")
        nattempts = Process.get(:connect_attempts, 0)
        if nattempts >= @maxattempts do
          Logger.error("FAILED TO CONNECT #{@maxattempts} TIMES IN A ROW. SHUTTING DOWN")
          :erlang.halt()
        else
          Process.put(:connect_attempts, nattempts+1)
          Logger.warn("RETRYING IN #{@sleep_sec} SECONDS")
          sleep_sec(@sleep_sec)
          connect(server_state, user_state)
        end
    end
  end

  defp sleep_sec(n), do: :timer.sleep(n * 1000)


  defp handshake(sock, server_state, user_state={_, _, info=%UserInfo{nickname: nick}}) do
    :random.seed(:erlang.monotonic_time)

    sock
    |> irc_cmd("PASS", "*")
    |> irc_cmd("NICK", nick)
    |> irc_cmd("USER", "#{nick} 0 * :BEAM")
    |> irc_identify(info.password)
    |> irc_join(info.channels)
    |> message_loop(server_state, user_state)
  end

  defp message_loop(sock, server_state=%State{hooks: hooks}, {module, state, info}) do
    retry = false
    receive do
      {__MODULE__, :internal, {:add_hook, id, f, opts}} ->
        server_state = Map.update!(server_state, :hooks,
                                        &HookHelpers.add_hook(&1, id, f, opts))

      {__MODULE__, :internal, {:remove_hook, id}} ->
        server_state = Map.update!(server_state, :hooks,
                                        &HookHelpers.remove_hook(&1, id))

      {__MODULE__, :internal, {:send_message, chan, msg}} ->
        irc_cmd(sock, "PRIVMSG", "#{chan} :#{msg}")

      {__MODULE__, :call, {caller_pid, ref}=from, msg} ->
        state = case module.handle_call(msg, from, state) do
          {:reply, reply, new_state} ->
            send(caller_pid, {:reply, ref, reply})
            new_state
        end

      {__MODULE__, :cast, msg} ->
        state = case module.handle_cast(msg, state) do
          {:noreply, new_state} -> new_state
        end

      {:tcp, ^sock, msg} ->
        msg = IO.iodata_to_binary(msg) |> String.strip
        Logger.info(msg)

        case translate_msg(msg) do
          nil   -> nil
          :ping -> irc_cmd(sock, "PONG", info.nickname)
          {:topic, _chan, _topic} -> nil

          {:privmsg, chan, sender, msg} ->
            try do
              HookHelpers.process_hooks({chan, sender, msg}, hooks, info, sock)
            rescue
              x -> Logger.info(inspect(x))
            end
        end

      {:tcp_closed, ^sock} ->
        Logger.warn("SOCKET CLOSE; RETRYING CONNECT IN #{@sleep_sec} SECONDS")
        retry = true

      {:tcp_error, ^sock, reason} ->
        Logger.warn("SOCKET ERROR: #{inspect reason}\nRETRYING CONNECT IN #{@sleep_sec} SECONDS")
        retry = true

      other ->
        state = case module.handle_info(other) do
          {:noreply, new_state} -> new_state
        end

      after @ping_sec * 1000 ->
        Logger.info("No ping message in #{@ping_sec} seconds. Retrying connect.")
        :gen_tcp.close(sock)
        retry = true
    end

    if retry do
      sleep_sec(@sleep_sec)
      connect(server_state, {module, state, info})
    else
      message_loop(sock, server_state, {module, state, info})
    end
  end
end
