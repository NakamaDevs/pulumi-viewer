defmodule PulumiViewerWeb.Router do
  use PulumiViewerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PulumiViewerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PulumiViewerWeb do
    pipe_through :browser

    live "/", StacksLive
    live "/resources", ResourcesLive
    live "/history", HistoryLive
    live "/sources/:source/stacks/:project/:stack", StackLive
    # one source (or the first one): the route before sources existed
    live "/stacks/:project/:stack", StackLive
  end

  # Read-only MCP server (checks and flags tools).
  forward "/mcp", PulumiViewerWeb.MCP

  # Other scopes may use custom stacks.
  # scope "/api", PulumiViewerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:pulumi_viewer, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PulumiViewerWeb.Telemetry
    end
  end
end
