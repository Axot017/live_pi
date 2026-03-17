defmodule LivePi.Config do
  @moduledoc """
  Runtime configuration access for LivePi services.
  """

  @app :live_pi

  def pi_module do
    Application.fetch_env!(@app, :pi_module)
  end

  def projects_module do
    Application.fetch_env!(@app, :projects_module)
  end

  def project_roots do
    @app
    |> Application.get_env(:project_roots, [])
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  def managed_clone_root do
    case Application.get_env(@app, :managed_clone_root) do
      nil -> nil
      path -> Path.expand(path)
    end
  end

  def pi_executable do
    Application.get_env(@app, :pi_executable, "pi")
  end

  def pi_default_args do
    Application.get_env(@app, :pi_default_args, [])
  end
end
