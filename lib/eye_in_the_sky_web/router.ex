defmodule EyeInTheSkyWeb.Router do
  use EyeInTheSkyWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug EyeInTheSkyWeb.Plugs.ValidateSession
    plug :fetch_live_flash
    plug :put_root_layout, html: {EyeInTheSkyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{}
    plug EyeInTheSkyWeb.Plugs.CspNonce
    plug :put_csp
  end

  defp put_csp(conn, _opts) do
    csp = build_csp(conn.assigns[:csp_nonce])
    put_resp_header(conn, "content-security-policy", csp)
  end

  if Mix.env() == :dev do
    defp build_csp(_nonce) do
      port = System.get_env("VITE_PORT", "5173")
      origin = "http://localhost:#{port}"
      ws_origin = "ws://localhost:#{port}"
      ip_origin = "http://127.0.0.1:#{port}"
      ip_ws_origin = "ws://127.0.0.1:#{port}"

      "default-src 'self'; " <>
        "script-src 'self' 'unsafe-inline' #{origin} #{ip_origin}; " <>
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " <>
        "font-src 'self' data: https://fonts.gstatic.com; " <>
        "img-src 'self' data: blob: #{origin} #{ip_origin}; " <>
        "connect-src 'self' #{ws_origin} #{ip_ws_origin}; " <>
        "frame-ancestors 'none'; " <>
        "object-src 'none'"
    end
  else
    defp build_csp(nonce) do
      script_src =
        if nonce, do: "script-src 'self' 'nonce-#{nonce}'; ", else: "script-src 'self'; "

      "default-src 'self'; " <>
        script_src <>
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " <>
        "font-src 'self' data: https://fonts.gstatic.com; " <>
        "img-src 'self' data: blob:; " <>
        "connect-src 'self'; " <>
        "frame-ancestors 'none'; " <>
        "object-src 'none'"
    end
  end

  pipeline :require_auth do
    plug EyeInTheSkyWeb.Plugs.RequireAuth
  end

  pipeline :session_auth do
    plug EyeInTheSkyWeb.Plugs.SessionAuth
  end

  pipeline :api do
    plug :accepts, ["json"]

    # plug Plug.Logger, log: :error  # disabled — log: :error logs ALL requests at error level, not just errors
    plug EyeInTheSkyWeb.Plugs.RateLimit, default: {60, :timer.minutes(1)}
    plug EyeInTheSkyWeb.Plugs.RequireAuth
  end

  # Unauthenticated JSON pipeline for inbound webhooks (auth handled per-controller)
  pipeline :accepts_json do
    plug :accepts, ["json"]

    # plug Plug.Logger, log: :error  # disabled — log: :error logs ALL requests at error level, not just errors
  end

  # Session-aware JSON pipeline without CSRF — safe for WebAuthn endpoints
  # (registration is token-gated; login uses WebAuthn challenge binding)
  pipeline :webauthn do
    plug :accepts, ["json"]

    # plug Plug.Logger, log: :error  # disabled — log: :error logs ALL requests at error level, not just errors
    plug :fetch_session
    plug EyeInTheSkyWeb.Plugs.RateLimit
  end

  # Browser-session JSON pipeline — for browser-facing JSON endpoints that use
  # cookie auth instead of Bearer tokens. No CSRF (fetch() API calls), but requires
  # a valid authenticated session. Returns JSON 401 (not redirect) on auth failure.
  pipeline :browser_json do
    plug :accepts, ["json"]

    # plug Plug.Logger, log: :error  # disabled — log: :error logs ALL requests at error level, not just errors
    plug :fetch_session
    plug EyeInTheSkyWeb.Plugs.JsonSessionAuth
    plug EyeInTheSkyWeb.Plugs.RateLimit
  end

  # Auth LiveView pages (HTML, with CSRF)
  scope "/auth", EyeInTheSkyWeb do
    pipe_through :browser

    live "/login", AuthLive, :login
    live "/register", AuthLive, :register
    delete "/logout", AuthController, :logout
  end

  # WebAuthn JSON endpoints (no CSRF — protected by token + challenge binding)
  scope "/auth", EyeInTheSkyWeb do
    pipe_through :webauthn

    post "/register/challenge", AuthController, :register_challenge
    post "/register/complete", AuthController, :register_complete
    post "/login/challenge", AuthController, :login_challenge
    post "/login/complete", AuthController, :login_complete
  end

  scope "/.well-known", EyeInTheSkyWeb do
    pipe_through :browser
    get "/webauthn", WellKnownController, :webauthn
  end

  # Push notification endpoints — browser-session auth, no Bearer token required
  scope "/api/v1", EyeInTheSkyWeb.Api.V1 do
    pipe_through :browser_json

    get "/push/vapid-public-key", PushController, :vapid_public_key
    post "/push/subscribe", PushController, :subscribe
    delete "/push/subscribe", PushController, :unsubscribe
  end

  scope "/", EyeInTheSkyWeb do
    pipe_through [:browser]

    live_session :app,
      on_mount: [
        EyeInTheSkyWeb.AuthHook,
        EyeInTheSkyWeb.FloatingChatLive,
        EyeInTheSkyWeb.NavHook
      ] do
      live "/chat", ChatLive, :index
      live "/canvases", CanvasLive, :index
      live "/canvases/:id", CanvasLive, :show
      live "/", AgentLive.Index, :index
      live "/usage", OverviewLive.Usage, :index
      live "/keybindings", OverviewLive.Keybindings, :index
      live "/skills", OverviewLive.Skills, :index
      live "/agents", OverviewLive.Agents, :index
      live "/config", OverviewLive.Config, :index
      live "/notifications", OverviewLive.Notifications, :index
      live "/settings", OverviewLive.Settings, :index
      live "/sessions", ProjectLive.Sessions, :index
      live "/teams", ProjectLive.Teams, :index
      live "/projects/:id", ProjectLive.Show, :show
      live "/projects/:id/sessions", ProjectLive.Sessions, :show
      live "/projects/:id/prompts", ProjectLive.Prompts, :show
      live "/projects/:id/prompts/new", ProjectLive.PromptNew, :new
      live "/projects/:id/prompts/:prompt_id", ProjectLive.PromptShow, :show
      live "/projects/:id/tasks", ProjectLive.Tasks, :show
      live "/projects/:id/kanban", ProjectLive.Kanban, :show
      live "/projects/:id/notes", ProjectLive.Notes, :show
      live "/projects/:id/files", ProjectLive.Files, :show
      live "/projects/:id/agents", ProjectLive.Agents, :show
      live "/projects/:id/jobs", ProjectLive.Jobs, :show
      live "/projects/:id/teams", ProjectLive.Teams, :index
      live "/projects/:id/teams/:team_id", ProjectLive.TeamShow, :show
      live "/projects/:id/config", ProjectLive.Config, :show
      live "/projects/:id/skills", ProjectLive.Skills, :show
      live "/components", ComponentsLive, :index
      live "/terminal", TerminalLive, :index
      live "/mockup", MockupLive, :index
      live "/dm/:session_id", DmLive, :show
      live "/notes/new", NoteLive.New, :new
      live "/notes/:id/edit", NoteLive.Edit, :edit
      live "/workspace/sessions", WorkspaceLive.Sessions, :index
      live "/workspace/tasks", WorkspaceLive.Tasks, :index
      live "/workspace/notes", WorkspaceLive.Notes, :index
      live "/iam/simulator", IAMLive.Simulator, :index
      live "/iam/policies", IAMLive.Policies, :index
      live "/iam/policies/new", IAMLive.PolicyNew, :new
      live "/iam/policies/:id/edit", IAMLive.PolicyEdit, :edit
    end
  end

  import Oban.Web.Router

  scope "/oban" do
    pipe_through [:browser, :session_auth]
    oban_dashboard("/")
  end

  scope "/api/v1", EyeInTheSkyWeb.Api.V1 do
    pipe_through :api

    # Health check
    get "/health", HealthController, :index

    # Sessions
    get "/sessions", SessionController, :index
    post "/sessions", SessionController, :create
    get "/sessions/:uuid", SessionController, :show
    patch "/sessions/:uuid", SessionController, :update
    post "/sessions/:uuid/end", SessionController, :end_session
    post "/sessions/:uuid/complete", SessionController, :complete
    post "/sessions/:uuid/waiting", SessionController, :waiting
    post "/sessions/:uuid/reopen", SessionController, :reopen
    post "/sessions/:uuid/archive", SessionController, :archive
    post "/sessions/:uuid/unarchive", SessionController, :unarchive
    post "/sessions/:uuid/tool-events", SessionController, :tool_event
    get "/sessions/:uuid/context", SessionController, :get_context
    patch "/sessions/:uuid/context", SessionController, :update_context
    get "/sessions/:uuid/tasks", TaskController, :list_for_session

    # Timers
    get "/sessions/:session_id/timer", TimerController, :show
    post "/sessions/:session_id/timer", TimerController, :schedule
    delete "/sessions/:session_id/timer", TimerController, :cancel

    # Commits
    get "/commits", CommitController, :index
    post "/commits", CommitController, :create

    # Notes
    get "/notes", NoteController, :index
    post "/notes", NoteController, :create
    get "/notes/:id", NoteController, :show
    patch "/notes/:id", NoteController, :update

    # Prompts
    get "/prompts", PromptController, :index
    post "/prompts", PromptController, :create
    get "/prompts/:id", PromptController, :show

    # Notifications
    post "/notifications", NotificationController, :create

    # Tasks
    get "/tasks", TaskController, :index
    post "/tasks", TaskController, :create
    get "/tasks/:id", TaskController, :show
    patch "/tasks/:id", TaskController, :update
    delete "/tasks/:id", TaskController, :delete
    post "/tasks/:id/annotations", TaskController, :annotate
    post "/tasks/:id/complete", TaskController, :complete
    post "/tasks/:id/claim", TaskController, :claim
    post "/tasks/:id/sessions", TaskController, :link_session
    get "/tasks/:id/sessions", TaskController, :list_sessions
    delete "/tasks/:id/sessions/:uuid", TaskController, :unlink_session
    post "/tasks/:id/tags", TaskController, :add_tag

    # Tags
    get "/tags", TagController, :index

    # Scheduled Jobs
    get "/jobs", JobController, :index
    post "/jobs", JobController, :create
    get "/jobs/:id", JobController, :show
    patch "/jobs/:id", JobController, :update
    delete "/jobs/:id", JobController, :delete
    post "/jobs/:id/run", JobController, :run

    # Projects
    get "/projects", ProjectController, :index
    post "/projects", ProjectController, :create
    get "/projects/:id", ProjectController, :show

    # Agents
    get "/agents", AgentController, :index
    post "/agents", AgentController, :create
    get "/agents/activity", AgentActivityController, :activity
    get "/agents/:id", AgentController, :show

    # Messages
    get "/messages/search", MessageSearchController, :search

    # Direct messages
    get "/dm", MessagingController, :list_dms
    post "/dm", MessagingController, :dm

    # Channels
    get "/channels", ChannelController, :index
    get "/channels/mine", ChannelController, :mine
    post "/channels", ChannelController, :create
    get "/channels/:channel_id/messages", ChannelMessageController, :index
    post "/channels/:channel_id/messages", ChannelMessageController, :create
    get "/channels/:channel_id/members", ChannelController, :list_members
    post "/channels/:channel_id/members", ChannelController, :join
    delete "/channels/:channel_id/members/:session_id", ChannelController, :leave

    # Teams
    get "/teams", TeamController, :index
    post "/teams", TeamController, :create
    get "/teams/:id", TeamController, :show
    patch "/teams/:id", TeamController, :update
    delete "/teams/:id", TeamController, :delete
    get "/teams/:team_id/members", TeamController, :list_members
    post "/teams/:team_id/members", TeamController, :join
    patch "/teams/:team_id/members/:member_id", TeamController, :update_member
    delete "/teams/:team_id/members/:member_id", TeamController, :leave
    post "/teams/:team_id/broadcast", TeamController, :broadcast
  end

  # IAM hook endpoint — unauthenticated (hooks run in Claude CLI process with no user session)
  scope "/api/v1", EyeInTheSkyWeb.Api.V1 do
    pipe_through [:accepts_json]

    post "/iam/decide", IAMController, :decide
    post "/iam/hook", IAMController, :decide
  end

  # Unauthenticated settings reads (read-only, no sensitive data)
  scope "/api/v1", EyeInTheSkyWeb.Api.V1 do
    pipe_through [:accepts_json]

    get "/settings/eits_workflow_enabled", SettingsController, :eits_workflow_enabled
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:eye_in_the_sky, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:browser, :session_auth]

      live_dashboard "/dashboard", metrics: EyeInTheSkyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
