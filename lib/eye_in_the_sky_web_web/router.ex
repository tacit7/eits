defmodule EyeInTheSkyWebWeb.Router do
  use EyeInTheSkyWebWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EyeInTheSkyWebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", EyeInTheSkyWebWeb do
    pipe_through :browser

    live_session :app do
      live "/", AgentLive.Index, :index
      live "/notes", OverviewLive.Notes, :index
      live "/tasks", OverviewLive.Tasks, :index
      live "/usage", OverviewLive.Usage, :index
      live "/skills", OverviewLive.Skills, :index
      live "/config", OverviewLive.Config, :index
      live "/jobs", OverviewLive.Jobs, :index
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
      live "/projects/:id/config", ProjectLive.Config, :show
      live "/projects/:id/agents", ProjectLive.Agents, :show
      live "/chat", ChatLive, :index
      live "/dm/:session_id", DmLive, :show
    end
  end

  # MCP Server — Streamable HTTP
  # Wrapped in MCPPlug to catch (EXIT) shutdown from hot-reload-induced transport restarts
  scope "/mcp" do
    forward "/", EyeInTheSkyWebWeb.MCPPlug, server: EyeInTheSkyWeb.MCP.Server
  end

  scope "/api/v1", EyeInTheSkyWebWeb.Api.V1 do
    pipe_through :api

    post "/sessions", SessionController, :create
    patch "/sessions/:uuid", SessionController, :update
    post "/commits", CommitController, :create
    post "/notes", NoteController, :create
    post "/prompts", PromptController, :create
    post "/session-context", SessionContextController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:eye_in_the_sky_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EyeInTheSkyWebWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
