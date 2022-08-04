defmodule Signet.MixProject do
  use Mix.Project

  def project do
    [
      app: :signet,
      version: "0.1.5",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Signet",
      description: "Lightweight Ethereum RPC client for Elixir",
      source_url: "https://github.com/hayesgm/signet",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ],
      package: package()
    ]
  end

  defp package() do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Geoffrey Hayes"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/hayesgm/signet"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Signet.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:jason, "~> 1.2"},
      {:httpoison, "~> 1.8"},
      {:google_api_cloud_kms, "~> 0.38.1", optional: true},
      {:ex_sha3, "~> 0.1"},
      {:curvy, "~> 0.3.0"},
      {:goth, "~> 1.3.0", optional: true},
      {:ex_rlp, "~> 0.5.4"},
      {:abi, "~> 0.1.20"}
    ]
  end
end
