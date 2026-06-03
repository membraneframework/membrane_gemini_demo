defmodule Membrane.Gemini.Demo.Mixfile do
  use Mix.Project

  @version "0.1.0"
  @github_url "https://github.com/membraneframework/membrane_gemini_demo"

  def project do
    [
      app: :membrane_gemini_demo,
      version: @version,
      elixir: "~> 1.13",

      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),

      # docs
      name: "Membrane Gemini Plugin demo",
      source_url: @github_url,
      homepage_url: "https://membrane.stream"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:membrane_core, "~> 1.0"},
      {:membrane_gemini_plugin, "~> 0.1.2"},
      {:membrane_portaudio_plugin, ">= 0.0.0"},
      {:membrane_realtimer_plugin, "~> 0.10.0"},
      {:membrane_ffmpeg_swresample_plugin, "~> 0.20.5"},
      {:membrane_raw_audio_parser_plugin, "~> 0.4.0"},
      {:termite, "~> 0.4.2"},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp dialyzer() do
    opts = [
      flags: [:error_handling]
    ]

    if System.get_env("CI") == "true" do
      # Store PLTs in cacheable directory for CI
      [plt_local_path: "priv/plts", plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
  end
end
