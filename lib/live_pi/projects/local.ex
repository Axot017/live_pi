defmodule LivePi.Projects.Local do
  @moduledoc """
  Default filesystem-backed project service.

  Phase 1 provides configuration-backed roots and placeholder operations.
  Phase 2 will add safe browsing, project detection, and cloning.
  """

  @behaviour LivePi.Projects

  alias LivePi.Config

  @impl true
  def roots do
    Config.project_roots()
  end

  @impl true
  def list_projects do
    []
  end

  @impl true
  def browse(nil) do
    case roots() do
      [root | _] -> {:ok, %{current_path: root, entries: []}}
      [] -> {:error, :no_project_roots_configured}
    end
  end

  def browse(path) when is_binary(path) do
    {:ok, %{current_path: Path.expand(path), entries: []}}
  end

  @impl true
  def select_project(_path) do
    {:error, :not_implemented}
  end

  @impl true
  def clone_project(_repo_url, _opts) do
    {:error, :not_implemented}
  end
end
