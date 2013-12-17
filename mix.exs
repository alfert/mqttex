defmodule Mqttex.Mixfile do
  use Mix.Project

  def project do
    [ app: :mqttex,
      version: "0.0.1",
      elixir: "~> 0.12.0",
      deps: deps,
      dialyzer: [paths: ["_build/shared/lib/mqttex/ebin"] ], 
      docs: [readme: true]
    ]
  end

  # Configuration for the OTP application
  def application do
    [ 
      mod: { Mqttex, [] },
      applications: [:kernel, :stdlib, :sasl, :elixir]
    ]
  end

  # Returns the list of dependencies in the format:
  # { :foobar, git: "https://github.com/elixir-lang/foobar.git", tag: "0.1" }
  #
  # To specify particular versions, regardless of the tag, do:
  # { :barbat, "~> 0.1", github: "elixir-lang/barbat.git" }
  defp deps do
    [
      { :properex, ">= 0.1", [github: "yrashk/properex"]},
      # LagerEx ist too old and does not compile in version 0.1
      # {:lagerex,"0.1", [github: "yrashk/lagerex", tag: "0.1"]},
      {:ranch,"0.9.0", [github: "extend/ranch", tag: "0.9.0"]},
      {:dialyxir,"0.2.2",[github: "jeremyjh/dialyxir"]},
      # Generate documentation with ex_doc
      { :ex_doc, github: "elixir-lang/ex_doc" }

    ]
  end
end
