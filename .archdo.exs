# Archdo configuration — generated for Phoenix project
[
  # Layer definitions
  layers: [
    interface: ~r/^EyeInTheSkyWeb\./,
    domain: ~r/^EyeInTheSky\.(?!Repo|Mailer)/,
    infrastructure: ~r/^EyeInTheSky\.(Repo|Mailer)/
  ],

  # Allowed dependency direction (interface → domain → infrastructure)
  allowed_deps: %{
    interface: [:domain, :infrastructure],
    domain: [:infrastructure],
    infrastructure: []
  },

  # Severity overrides
  overrides: [
    # application.ex starting EyeInTheSkyWeb.Endpoint is intentional Phoenix OTP structure
    # (the Application module is the entry point that boots all children including the web stack)
    {:"1.1", :ignore},
    # Process.exit(pid, :kill) in sdk.ex/codex/sdk.ex/gemini/stream_handler.ex are
    # intentional streaming kill paths — force-terminating LLM stream processes on timeout/cancel.
    {:"5.39", :ignore},
    # spawn_link in cli/port.ex is the Erlang port bridge process — supervised at call site.
    {:"5.1", :ignore}
  ]
]
