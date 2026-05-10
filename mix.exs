defmodule EyeInTheSky.MixProject do
  use Mix.Project

  def project do
    [
      app: :eye_in_the_sky,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      releases: [
        eye_in_the_sky: [
          validate_compile_env: false,
          steps: [:assemble, &maybe_codesign/1],
          entitlements: "#{__DIR__}/src-tauri/Entitlements.plist"
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {EyeInTheSky.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "dev_lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "dev_lib"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:gemini_cli_sdk, "~> 0.2.0"},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:live_svelte, "~> 0.18.0-rc0"},
      {:phoenix_vite, "~> 0.4"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      # {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:oban, "~> 2.19"},
      {:oban_web, "~> 2.11"},
      {:crontab, "~> 1.1"},
      {:tz, "~> 0.28"},
      {:wax_, "~> 0.7.0"},
      {:web_push_encryption, "~> 0.3"},
      {:dotenvy, "~> 0.8.0"},
      {:hammer, "~> 7.0"},
      {:remote_ip, "~> 1.2"},
      {:hexdocs_mcp, "~> 0.5.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:archdo,
       github: "BadBeta/archdo",
       ref: "1e651d57096122d8125490e78e963db4aa956266",
       only: [:dev, :test],
       runtime: false},
      {:req, "~> 0.5"},
      {:elixirkit, github: "livebook-dev/elixirkit"},
      {:erlexec, "~> 2.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  # Only codesign when APPLE_SIGNING_IDENTITY is set.
  # In local dev/CI without a certificate, skip silently.
  # In CI with a certificate, set APPLE_SIGNING_IDENTITY to run codesign.
  defp maybe_codesign(release) do
    if System.get_env("APPLE_SIGNING_IDENTITY") do
      ElixirKit.Release.codesign(release)
    else
      release
    end
  end

  defp docs do
    [
      main: "EyeInTheSky",
      source_url: "https://github.com/tacit7/eits-web",
      extras: [
        "README.md",
        "docs/SETUP.md": [title: "Setup"],
        "docs/REST_API.md": [title: "REST API"],
        "docs/EITS_CLI.md": [title: "EITS CLI"],
        "docs/AGENT_WORKER_QUEUE.md": [title: "Agent Worker Queue"],
        "docs/AGENT_DEFINITIONS.md": [title: "Agent Definitions"],
        "docs/IAM_POLICY.md": [title: "IAM Policy"],
        "docs/IAM_HOOK_INSTALL.md": [title: "IAM Hook Install"],
        "docs/CHAT.md": [title: "Chat"],
        "docs/DM_FEATURES.md": [title: "DM Features"],
        "docs/KANBAN.md": [title: "Kanban"],
        "docs/CANVAS.md": [title: "Canvas"],
        "docs/TERMINAL_PTY.md": [title: "Terminal / PTY"],
        "docs/VIM_NAV.md": [title: "Vim Navigation"],
        "docs/COMMAND_PALETTE.md": [title: "Command Palette"],
        "docs/SEARCH.md": [title: "Search"],
        "docs/WORKERS.md": [title: "Workers"],
        "docs/EVENTS.md": [title: "Events"],
        "docs/SESSION_MANAGER.md": [title: "Session Manager"],
        "docs/CODEX_SDK.md": [title: "Codex SDK"],
        "docs/RAIL_MENU.md": [title: "Rail Menu"],
        "docs/EITS_HOOKS.md": [title: "EITS Hooks"],
        "docs/SECURITY.md": [title: "Security"],
        "docs/MOBILE.md": [title: "Mobile"],
        "docs/ATTACHMENTS.md": [title: "Attachments"],
        "docs/PRODUCTION.md": [title: "Production"],
        "docs/CODE_GUIDELINES.md": [title: "Code Guidelines"]
      ],
      groups_for_extras: [
        "Getting Started": [
          "README.md",
          "docs/SETUP.md",
          "docs/PRODUCTION.md",
          "docs/CODE_GUIDELINES.md"
        ],
        "API & CLI": [
          "docs/REST_API.md",
          "docs/EITS_CLI.md"
        ],
        "Core Features": [
          "docs/AGENT_WORKER_QUEUE.md",
          "docs/AGENT_DEFINITIONS.md",
          "docs/SESSION_MANAGER.md",
          "docs/EVENTS.md",
          "docs/WORKERS.md"
        ],
        "IAM": [
          "docs/IAM_POLICY.md",
          "docs/IAM_HOOK_INSTALL.md",
          "docs/SECURITY.md"
        ],
        "UI Features": [
          "docs/CHAT.md",
          "docs/DM_FEATURES.md",
          "docs/KANBAN.md",
          "docs/CANVAS.md",
          "docs/TERMINAL_PTY.md",
          "docs/VIM_NAV.md",
          "docs/COMMAND_PALETTE.md",
          "docs/RAIL_MENU.md",
          "docs/MOBILE.md",
          "docs/SEARCH.md"
        ],
        "Integrations": [
          "docs/CODEX_SDK.md",
          "docs/EITS_HOOKS.md",
          "docs/ATTACHMENTS.md"
        ]
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "phoenix_vite.npm assets install"],
      "assets.build": [
        "compile",
        "tailwind eye_in_the_sky",
        "phoenix_vite.npm vite build",
        "cmd --cd assets npx vite build --ssr js/server.js --outDir ../priv/svelte"
      ],
      "assets.deploy": [
        "tailwind eye_in_the_sky --minify",
        "phoenix_vite.npm vite build",
        "cmd --cd assets npx vite build --ssr js/server.js --outDir ../priv/svelte",
        "phx.digest"
      ],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
