defmodule Chatty do
  use Application

  alias Chatty.ConnServer

  def start(_type, _args) do
    Chatty.Supervisor.start_link
  end

  ###

  @doc """
  Add a hook on the currently open connection.

  ## Arguments

    * `id` - arbitrary atom to identify the hook when calling `remove_hook/1`
    * `f` - function of 2 arguments that will be called on incoming messages
    * `opts` - a keyword list of options

  ## Hook options

    * `in: :text | :token` - specify the type of the argument that the hook
      function will be called with. `:text` means that the message will be
      passed to the function as is. `:token` means that it will be split into
      words and the resulting list will be passed to the function.

    * `direct: <boolean>` - if `true`, the hook will be triggered only on those
      messages that are addressed to the client's nickname in the following
      form:

          <nickname>: message goes here

    * `exclusive: <boolean>` - if `true`, the hook will be triggered only if no
      other hook before it has reported successful processing of the message.

    * `channel: <string>` - the hook will only be active on the specified
      channel

  ## Hook results

  A hook function may return one of the following values:

    * `{:msg, <string>}` - send a message to the channel where it was received

    * `{:notice, <string>}` - send a notice to the channel where it was received

    * `{:reply, <string>}` - send a message addressed to the original sender

    * `{:reply, <receiver>, <string>}` - send a message addressed to
      `<receiver>` on the channel

    * `<list>` - a list containing any of the above values which will result in
      one message for each list item

  """
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
