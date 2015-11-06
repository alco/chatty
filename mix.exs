defmodule Chatty.Mixfile do
  use Mix.Project

  def project do
    [
      app: :chatty,
      version: "0.1.0",
      elixir: "~> 1.0",
    ]
  end

  def application do
    [
      applications: [:logger, :inets, :crypto, :ssl],
      mod: {Chatty.Application, []},
    ]
  end

  # no deps
  # --alco
end
