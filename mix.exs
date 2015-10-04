defmodule Chatty.Mixfile do
  use Mix.Project

  def project do
    [
      app: :chatty,
      version: "0.1.0",
      elixir: ">= 0.14.1 and < 2.0.0",
    ]
  end

  def application do
    [
      applications: [:logger, :inets, :crypto, :ssl],
      mod: {Chatty, []},
    ]
  end

  # no deps
  # --alco
end
