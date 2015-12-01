defmodule Chatty do
  @moduledoc """
  This module defines the public API for interacting with the IRC connection and the hook mechanism.

  ## How hooks are invoked

  When a new message arrives, the whole list of hooks is enumerated to see which ones are applicable
  to the message (based on parameters like the message kind, hook options, etc.). Then each
  applicable hook is executed in a separate `Task`, concurrently with the others. Finally, all of
  the hooks that returned a non-nil value (and didn't crash or time out) will have their result sent
  back over the IRC connection.

  The only exception to the above algorithm is when a hook is added as `exclusive`. In that case,
  its result will only be sent back if no other hook has returned a value.
  """

  alias Chatty.Connection

  @typep singular_response
         :: {:msg, String.t}
          | {:notice, String.t}
          | {:reply, String.t}
          | {:reply, String.t, String.t}
  @type response :: singular_response | [singular_response] | nil

  @doc """
  Add a hook that will trigger on incoming messages, whether they appear on a channel or are sent
  directly to the connected user's nickname.

  ## Arguments

    * `id` - arbitrary atom to identify the hook when calling `remove_hook/1`

    * `f` - function of 3 arguments that will be called on incoming messages where the arguments
      are:

        - `message` – the message that was sent;

        - `sender` – the nickname of the user who sent the message;

        - `channel` – the channel on which the message was sent; can be the nickname of the
          connected user;

    * `options` - a dict of options

  ## Hook options

    * `in: :text | :tokens` - specify the type of the `message` argument that the hook function will
    be called with. `:text` means that the message will be passed to the function as is. `:tokens`
    means that it will be split into words and the resulting list will be passed to the function.

    * `direct: <boolean>` - if `true`, the hook will be triggered only on those messages that are
    addressed to the connected user's nickname in the following form:

          <nickname>: message goes here

    * `exclusive: <boolean>` - if `true`, the hook will be triggered only if no other hook has
      returned a result.

    * `channel: <string>` - the hook will be active only on the specified channel, as opposed
      to all channels that the connected user is present in.

  ## Hook results

  A hook function may return one of the following values:

    * `nil` - nothing will be sent back

    * `{:msg, <string>}` - send a message to the channel where it was received

    * `{:notice, <string>}` - send a notice to the channel where it was received

    * `{:reply, <string>}` - send a message addressed to the original sender

    * `{:reply, <receiver>, <string>}` - send a message addressed to `<receiver>`

    * `<list>` - a list containing any of the above values which will result in one message for each
      list item

  """
  @spec add_privmsg_hook(atom, ((String.t | [String.t], String.t, String.t) -> response), Dict.t)
        :: :ok | {:error, term}
  def add_privmsg_hook(id, f, opts \\ []) do
    Chatty.HookManager.add_hook(:privmsg, id, f, opts)
  end

  @doc """
  Add a hook that will trigger whenever the channel topic changes.

  ## Arguments

    * `id` - arbitrary atom to identify the hook when calling `remove_hook/1`

    * `f` - function of 3 arguments:

        - `topic` – the new topic;

        - `sender` – the nickname of the user who changed the topic;

        - `channel` – the channel on which the topic was changed;

    * `options` - a dict of options

  ## Hook options

    * `channel: <string>` - the hook will be active only on the specified channel, as opposed
      to all channels that the connected user is present in.

  ## Hook results

  The same return values as for `add_privmsg_hook/3` are supported.

  """
  @spec add_topic_hook(atom, ((String.t, String.t, String.t) -> response), Dict.t)
        :: :ok | {:error, term}
  def add_topic_hook(id, f, opts \\ []) do
    # FIXME: implement different option parsing for :topic hooks
    Chatty.HookManager.add_hook(:topic, id, f, opts)
  end

  @doc """
  Add a hook that will trigger whenever user joins or leave a channel.

  ## Arguments

    * `id` - arbitrary atom to identify the hook when calling `remove_hook/1`

    * `f` - function of 3 arguments:

        - `event` – the type of the event, either `:join` or `:part`;

        - `sender` – the nickname of the user who changed joined or left;

        - `channel` – the channel on which the event happened;

    * `options` - a dict of options

  ## Hook options

    * `channel: <string>` - the hook will be active only on the specified channel, as opposed
      to all channels that the connected user is present in.

  ## Hook results

  The same return values as for `add_privmsg_hook/3` are supported.

  """
  @spec add_presence_hook(atom, ((:join | :part, String.t, String.t) -> response), Dict.t)
        :: :ok | {:error, term}
  def add_presence_hook(id, f, opts \\ []) do
    # FIXME: implement different option parsing for :presence hooks
    Chatty.HookManager.add_hook(:presence, id, f, opts)
  end

  @doc """
  Remove a previously added hook.
  """
  @spec remove_hook(atom) :: :ok | :not_found
  def remove_hook(id) do
    Chatty.HookManager.remove_hook(id)
  end

  @spec send_message(String.t, String.t) :: :ok
  def send_message(chan, msg) do
    Connection.send_message(Chatty.Connection, chan, msg)
  end

  def init_hooks() do
    add_privmsg_hook :ping, &Chatty.Hooks.PingHook.run/3, direct: true
    add_privmsg_hook :rude, &Chatty.Hooks.RudeReplyHook.run/3, direct: true, exclusive: true
    add_topic_hook :topic, &Chatty.Hooks.TopicHook.run/3
    add_presence_hook :presence, &Chatty.Hooks.PresenceHook.run/3
  end
end
