defmodule Salvo.Mixfile do
  use Mix.Project

  def project do
    [app: :salvo,
     version: "0.1.0",
     elixir: "~> 1.3",
     description: description(),
     package: package(),
     name: "Salvo",
     source_url: "https://github.com/zambal/salvo",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [extra_applications: []]
  end

  defp description do
    """
    Experimental websocket server and client leveraging Elixir streams.
    """
  end

  defp package do
    [
      name: :salvo,
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Vincent Siliakus"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/zambal/salvo"}
    ]
  end

  defp deps do
    [{:ranch, git: "https://github.com/ninenines/ranch", ref: "master", override: true},
     {:gun, git: "https://github.com/ninenines/gun", tag: "1.0.0-pre.2"},
     {:cowboy, git: "https://github.com/ninenines/cowboy", tag: "2.0.0-pre.8"},
     {:ex_doc, "~> 0.15", only: :dev, runtime: false}]
  end
end
