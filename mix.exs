defmodule Signet.MixProject do
  use Mix.Project

  def project do
    [
      app: :signet,
      version: "1.0.0-beta4",
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
      files: ["lib", "mix.exs", "README*", "LICENSE*", "test/support"],
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
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.31.1", only: :dev, runtime: false},
      {:jason, "~> 1.4.1"},
      {:httpoison, "~> 2.2"},
      {:google_api_cloud_kms, "~> 0.38.1", optional: true},
      {:ex_sha3, "~> 0.1.4"},
      {:curvy, "~> 0.3.1"},
      {:goth, "~> 1.4.3", optional: true},
      {:ex_rlp, "~> 0.6.0"},
      {:abi, "~> 1.0.0-alpha3"},
      {:junit_formatter, "~> 3.3.1", only: [:test]}
    ]
  end
end
