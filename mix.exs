defmodule Chatty.Mixfile do
  use Mix.Project

  def project do
    [
      app: :chatty,
      version: "0.5.0",
      elixir: "~> 1.0",
      deps: deps(),
      description: description(),
      package: package(),
    ]
  end

  def application do
    [
      applications: [:logger, :inets, :crypto, :ssl],
      mod: {Chatty.Application, []},
    ]
  end

  defp description do
    "A basic IRC client that is most useful for writing a bot."
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Alexei Sholik"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/alco/chatty",
      }
    ]
  end

  defp deps do
    [{:ex_doc, "> 0.0.0", only: [:dev]}]
  end
end
