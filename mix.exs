defmodule Chatty.Mixfile do
  use Mix.Project

  def project do
    [
      app: :chatty,
      version: "0.0.1",
      elixir: "~> 0.14.1",
    ]
  end

  def application do
    [
      applications: [:inets, :crypto, :ssl],
      mod: {Chatty.Application, []},
    ]
  end

  # no deps
  # --alco
end
