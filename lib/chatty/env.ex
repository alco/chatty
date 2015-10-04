defmodule Chatty.Env do
  def get(key, default) do
    case Application.fetch_env(:chatty, key) do
      {:ok, value} -> value
      :error -> default
    end
  end
end
