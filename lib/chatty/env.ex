defmodule Chatty.Env do
  @moduledoc """
  A convenience module that wraps env-related functions from `Application`.
  """

  def get(key, default) do
    Application.get_env(:chatty, key, default)
  end
end
