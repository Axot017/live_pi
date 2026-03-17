defmodule LivePiWeb.Router do
  use LivePiWeb, :router

  import Plug.Conn

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LivePiWeb.Layouts, :root}
    plug :ensure_browser_session_id
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LivePiWeb do
    pipe_through :browser

    live "/", WorkspaceLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", LivePiWeb do
  #   pipe_through :api
  # end

  defp ensure_browser_session_id(conn, _opts) do
    case get_session(conn, :browser_session_id) do
      nil -> put_session(conn, :browser_session_id, new_browser_session_id())
      _session_id -> conn
    end
  end

  defp new_browser_session_id do
    12
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:live_pi, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LivePiWeb.Telemetry
    end
  end
end
