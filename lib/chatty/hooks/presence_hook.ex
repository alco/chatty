defmodule Chatty.Hooks.PresenceHook do
  def run(chan, kind, user) do
    IO.puts "User #{inspect user} #{kind}ed the channel #{inspect chan}"
    case kind do
      :join -> {:reply, user, "Hey, how are you?"}
      :part -> {:msg, "See you next time, #{user}"}
    end
  end
end
