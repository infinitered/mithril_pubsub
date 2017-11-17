defmodule Mithril.PubSub.MixProject do
  use Mix.Project

  def project do
    [
      app: :mithril_pubsub,
      version: "0.1.0",
      build_path: "_build",
      config_path: "config/config.exs",
      deps_path: "deps",
      lockfile: "mix.lock",
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def elixirc_paths(:test), do: ["lib", "test/support"]
  def elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "README",
      extras: ["README.md"],
      assets: "assets"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_pubsub, "~> 1.0.0"},
      {:ex_doc, ">= 0.0.0", only: [:dev, :test]}
    ]
  end
end