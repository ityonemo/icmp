defmodule Icmp.MixProject do
  use Mix.Project

  def project do
    [
      app: :icmp,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: start_permanent(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.detail": :test, "coveralls.post": :test, "coveralls.html": :test],
      source_url: "https://github.com/ityonemo/icmp",
      package: package(),
    ]
  end

  def start_permanent() do
    (Mix.env() == :prod) and Application.get_env(:icmp, :active, true)
  end

  defp description do
    "An ICMP ping client library"
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/ityonemo/icmp"}
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Icmp.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/_support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:net_address, "~> 0.2.1"},

      # static analysis tools.
      {:credo, "~> 1.1", only: [:test, :dev], runtime: false},
      {:dialyxir, "~> 0.5.1", only: :dev, runtime: false},
      {:licensir, "~> 0.4.2", only: :dev, runtime: false},
      {:ex_doc, "~> 0.20.2", only: :dev, runtime: false},

      # testing tools
      {:mox, "~> 0.5", only: :test},
      {:excoveralls, "~> 0.11.1", only: :test}
    ]
  end
end
