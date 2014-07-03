defmodule Chatty.Logger do
  @moduledoc false

  def log(msg) do
    log(:info, msg)
  end

  def log(:info, msg) do
    if Application.get_env(:chatty, :logging_enabled) do
      IO.write "[chatty] "
      IO.puts msg
    end
  end
end
