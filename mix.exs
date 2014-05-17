defmodule Mqttex.Mixfile do
  use Mix.Project

  
  def project do
    elixirc_defaults = [:debug_info, :ignore_module_conflict, :docs]
    [ app: :mqttex,
      version: "0.0.1",
      elixir: "~> 0.13",
      elixirc_options: elixirc_defaults ++ options(Mix.env),
      deps: deps,
      dialyzer: [paths: ["_build/shared/lib/mqttex/ebin"] ], 
      test_coverage: [tool: Coverex.Task],
      docs: [readme: true]
    ]
  end

  # Configuration for the OTP application
  def application do
    [ 
      mod: { Mqttex, [] },
      applications: [:kernel, :stdlib, :sasl, :elixir, :exlager],
      # standard configuration
      env: [
        port: 1178,  # default port is 1883, but mosquito is also running at home.
        ssl_port: 8883,
        default_user: "guest",
        default_passwd: "guest",
        lager: [
          colored: true
        ]
      ]
    ]
  end

  # Returns the list of dependencies in the format:
  # { :foobar, git: "https://github.com/elixir-lang/foobar.git", tag: "0.1" }
  #
  # To specify particular versions, regardless of the tag, do:
  # { :barbat, "~> 0.1", github: "elixir-lang/barbat.git" }
  defp deps do
    [
      # { :properex, ">= 0.1", [github: "yrashk/properex"]},
      {:exlager, ~r".*",[github: "khia/exlager"]},
      {:ranch,"0.9.0", [github: "extend/ranch", tag: "0.9.0"]},
      {:dialyxir,"0.2.3",[github: "jeremyjh/dialyxir"]},
      # Generate documentation with ex_doc
      { :ex_doc, github: "elixir-lang/ex_doc" },
      # Cover tests
      #{ :coverex, [path: "../coverex"] }
      {:coverex, "~> 0.0.1"}
    ]
  end

  # Specific compilation options, e.g. for Lager
  defp options(env) when env in [:dev, :test] do
    [exlager_level: :debug, exlager_truncation_size: 8096]
  end
end
