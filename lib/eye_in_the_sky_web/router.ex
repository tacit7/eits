defmodule EyeInTheSkyWeb.Router do
  use EyeInTheSkyWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug EyeInTheSkyWeb.Plugs.ValidateSession
    plug :fetch_live_flash
    plug :put_root_layout, html: {EyeInTheSkyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :require_auth do
    plug EyeInTheSkyWeb.Plugs.RequireAuth
  end

  pipeline :session_auth do
    plug EyeInTheSkyWeb.Plugs.SessionAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug EyeInTheSkyWeb.Plugs.RateLimit, default: {60, :timer.minutes(1)}
    plug EyeInTheSkyWeb.Plugs.RequireAuth
  end

  # Unauthenticated JSON pipeline for inbound webhooks (auth handled per-controller)
  pipeline :accepts_json do
    plug :accepts, ["json"]
  end

  # Session-aware JSON pipeline without CSRF — safe for WebAuthn endpoints
  # (registration is token-gated; login uses WebAuthn challenge binding)
  pipeline :webauthn do
    plug :accepts, ["json"]
    plug :fetch_session
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

  scope "/", EyeInTheSkyWeb do
    pipe_through [:browser]

    live_session :app,
      on_mount: [
        EyeInTheSkyWeb.AuthHook,
        EyeInTheSkyWeb.FabHook,
        EyeInTheSkyWeb.NavHook
      ] do
      live "/", AgentLive.Index, :index
      live "/notes", OverviewLive.Notes, :index
      live "/tasks", OverviewLive.Tasks, :index
      live "/usage", OverviewLive.Usage, :index
      live "/skills", OverviewLive.Skills, :index
      live "/config", OverviewLive.Config, :index
      live "/jobs", OverviewLive.Jobs, :index
      live "/notifications", OverviewLive.Notifications, :index
      live "/settings", OverviewLive.Settings, :index
      live "/sessions", SessionLive.Index, :index
      live "/prompts", PromptLive.Index, :index
      live "/prompts/new", PromptLive.New, :new
      live "/prompts/:id", PromptLive.Show, :show
      live "/projects/:id", ProjectLive.Show, :show
      live "/projects/:id/sessions", ProjectLive.Sessions, :show
      live "/projects/:id/prompts", ProjectLive.Prompts, :show
      live "/projects/:id/tasks", ProjectLive.Tasks, :show
      live "/projects/:id/kanban", ProjectLive.Kanban, :show
      live "/projects/:id/notes", ProjectLive.Notes, :show
      live "/projects/:id/files", ProjectLive.Files, :show
      live "/projects/:id/agents", ProjectLive.Agents, :show
      live "/projects/:id/jobs", ProjectLive.Jobs, :show
      live "/projects/:id/config", ProjectLive.Config, :show
      live "/mockup", MockupLive, :index
      live "/teams", TeamLive.Index, :index
      live "/chat", ChatLive, :index
      live "/dm/:session_id", DmLive, :show
      live "/notes/new", NoteLive.New, :new
      live "/notes/:id/edit", NoteLive.Edit, :edit
    end
  end

  import Oban.Web.Router

  scope "/oban" do
    pipe_through [:browser, :session_auth]
    oban_dashboard("/")
  end

  scope "/api/v1", EyeInTheSkyWeb.Api.V1 do
    pipe_through :api

    # Sessions
    get "/sessions", SessionController, :index
    post "/sessions", SessionController, :create
    get "/sessions/:uuid", SessionController, :show
    patch "/sessions/:uuid", SessionController, :update
    post "/sessions/:uuid/end", SessionController, :end_session
    post "/sessions/:uuid/tool-events", SessionController, :tool_event
    get "/sessions/:uuid/context", SessionController, :get_context
    patch "/sessions/:uuid/context", SessionController, :update_context

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
    post "/tasks/:id/sessions", TaskController, :link_session
    delete "/tasks/:id/sessions/:uuid", TaskController, :unlink_session

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
    get "/agents/:id", AgentController, :show

    # Push notifications
    get "/push/vapid-public-key", PushController, :vapid_public_key
    post "/push/subscribe", PushController, :subscribe
    delete "/push/subscribe", PushController, :unsubscribe

    # Messaging
    post "/dm", MessagingController, :dm
    get "/channels", MessagingController, :list_channels
    get "/channels/:channel_id/messages", MessagingController, :list_channel_messages
    post "/channels/:channel_id/messages", MessagingController, :send_channel_message

    # Teams
    get "/teams", TeamController, :index
    post "/teams", TeamController, :create
    get "/teams/:id", TeamController, :show
    delete "/teams/:id", TeamController, :delete
    get "/teams/:team_id/members", TeamController, :list_members
    post "/teams/:team_id/members", TeamController, :join
    patch "/teams/:team_id/members/:member_id", TeamController, :update_member
    delete "/teams/:team_id/members/:member_id", TeamController, :leave
  end

  # Gitea webhooks — no Bearer auth; controller validates HMAC signature from Gitea
  scope "/api/v1", EyeInTheSkyWeb.Api.V1 do
    pipe_through [:accepts_json]

    post "/webhooks/gitea", GiteaWebhookController, :handle
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
