defmodule LivePi do
  @moduledoc """
  Public application facade for workspace services.
  """

  alias LivePi.Chat
  alias LivePi.Config
  alias LivePi.Pi
  alias LivePi.Projects

  defdelegate start_session(browser_session_id, project_path, opts \\ []), to: Chat
  defdelegate subscribe(session_ref, subscriber \\ self()), to: Chat
  defdelegate prompt(session_ref, message, opts \\ []), to: Chat
  defdelegate abort(session_ref), to: Chat
  defdelegate reset_session(session_ref, opts \\ []), to: Chat, as: :reset
  defdelegate session_state(session_ref), to: Chat, as: :state
  defdelegate session_messages(session_ref), to: Chat, as: :messages

  defdelegate project_roots(), to: Projects, as: :roots
  defdelegate browse_projects(path \\ nil), to: Projects, as: :browse
  defdelegate list_projects(), to: Projects
  defdelegate select_project(path), to: Projects
  defdelegate clone_project(repo_url, opts \\ []), to: Projects

  def pi_module, do: Config.pi_module()
  def projects_module, do: Config.projects_module()
  def pi_executable, do: Pi.pi_executable()
  def pi_default_args, do: Pi.pi_default_args()
  def managed_clone_root, do: Config.managed_clone_root()
end
