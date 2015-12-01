defmodule Chatty.Hooks.PresenceHook do
  def run(event, sender, chan) do
    IO.puts "User #{inspect sender} #{event}ed the channel #{inspect chan}"
    case event do
      :join -> {:reply, sender, "Hey, how are you?"}
      :part -> {:msg, "See you next time, #{sender}"}
    end
  end
end
