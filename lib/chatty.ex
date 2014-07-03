defmodule Chatty do
  alias Chatty.ConnServer

  def add_hook(id, f, opts \\ []) do
    ConnServer.add_hook(Chatty.Conn, id, f, opts)
  end

  def remove_hook(id) do
    ConnServer.remove_hook(Chatty.Conn, id)
  end

  def send_message(chan, msg) do
    ConnServer.send_message(Chatty.Conn, chan, msg)
  end
end
