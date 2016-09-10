defmodule Chatty.Hooks.PingHook do
  @replies [
    "pong", "zap", "spank", "pow", "bang", "ka-pow", "woosh", "smack", "pink",
  ]
  @num_replies Enum.count(@replies)

  def run(text, _sender, _chan) do
    case String.downcase(text) do
      "ping" ->
        {:reply, Enum.at(@replies, :rand.uniform(@num_replies)-1)}

      _ -> nil
    end
  end
end
