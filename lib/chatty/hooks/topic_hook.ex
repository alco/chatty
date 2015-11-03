defmodule Chatty.Hooks.TopicHook do
  def run(chan, sender, topic) do
    IO.puts "#{sender} changed topic on channel #{inspect chan} to #{inspect topic}"
    # TODO: why simply :reply doesn't work?
    {:reply, sender, "I dig your topic"}
  end
end
