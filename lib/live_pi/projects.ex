defmodule LivePi.Projects do
  @moduledoc """
  Behaviour and facade for server-side project discovery and cloning.
  """

  alias LivePi.Config
  alias LivePi.Projects.Project

  @type browse_entry :: %{
          name: String.t(),
          path: String.t(),
          type: :directory,
          selectable?: boolean()
        }

  @callback roots() :: [String.t()]
  @callback list_projects() :: [Project.t()]
  @callback browse(String.t() | nil) ::
              {:ok, %{current_path: String.t(), entries: [browse_entry()]}} | {:error, term()}
  @callback select_project(String.t()) :: {:ok, Project.t()} | {:error, term()}
  @callback clone_project(String.t(), keyword()) :: {:ok, Project.t()} | {:error, term()}

  def roots do
    impl().roots()
  end

  def list_projects do
    impl().list_projects()
  end

  def browse(path \\ nil) do
    impl().browse(path)
  end

  def select_project(path) when is_binary(path) do
    impl().select_project(path)
  end

  def clone_project(repo_url, opts \\ []) when is_binary(repo_url) and is_list(opts) do
    impl().clone_project(repo_url, opts)
  end

  defp impl do
    Config.projects_module()
  end
end
