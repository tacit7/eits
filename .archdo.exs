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
    {:"5.1", :ignore},
    # 6.34 false positive: put_csp/2 in router.ex IS referenced via `plug :put_csp` macro
    # (archdo doesn't track plug atoms as call sites)
    {:"6.34", :ignore},
    # 5.20 false positive: Process.monitor in sdk.ex:224 is inside a Task with an explicit
    # `receive do {:DOWN, _ref, :process, ^caller_pid, _reason} -> ...` clause (line 237).
    # archdo only checks for handle_info clauses; explicit receive blocks aren't recognized.
    {:"5.20", :ignore}
  ]
]
