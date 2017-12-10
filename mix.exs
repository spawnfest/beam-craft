defmodule BeamCraft.Mixfile do
  use Mix.Project

  def project do
    [
      app: :beam_craft,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      env: [port: 5555, server_name: "BeamCraft Server", motd: "Elixir Minecraft Server!"],
      extra_applications: [:logger],
      mod: {BeamCraft.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ranch, "~> 1.4.0"},
      {:binary, "~> 0.0.4"},
      {:ex_doc, "~> 0.16", only: :dev},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false}
    ]
  end
end
