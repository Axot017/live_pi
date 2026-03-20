defmodule LivePi.PiSessions do
  @moduledoc false

  alias LivePi.PiSession

  def ensure_started(nil), do: {:error, :no_project}

  def ensure_started(project) do
    case Registry.lookup(LivePi.PiSessionRegistry, project.id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(LivePi.PiSessionSupervisor, {PiSession, project})
        |> case do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end

  def snapshot(project_id), do: PiSession.snapshot(project_id)
  def send_prompt(project_id, message), do: PiSession.send_prompt(project_id, message)
  def topic(project_id), do: PiSession.topic(project_id)
end
