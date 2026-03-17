defmodule LivePi.Chat do
  @moduledoc """
  Thin orchestration layer for workspace chat actions.

  The concrete streaming workflow will be expanded once the pi RPC transport
  is implemented.
  """

  alias LivePi.Pi

  def start_session(browser_session_id, project_path, opts \\ []) do
    Pi.start_session(
      Keyword.merge(opts,
        browser_session_id: browser_session_id,
        project_path: project_path,
        subscriber: Keyword.get(opts, :subscriber, self())
      )
    )
  end

  def subscribe(session_ref, subscriber \\ self()) do
    Pi.subscribe(session_ref, subscriber)
  end

  def prompt(session_ref, message, opts \\ []) do
    Pi.prompt(session_ref, message, opts)
  end

  def abort(session_ref) do
    Pi.abort(session_ref)
  end

  def reset(session_ref, opts \\ []) do
    Pi.new_session(session_ref, opts)
  end

  def state(session_ref) do
    Pi.get_state(session_ref)
  end

  def messages(session_ref) do
    Pi.get_messages(session_ref)
  end
end
