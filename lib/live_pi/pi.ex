defmodule LivePi.Pi do
  @moduledoc """
  Behaviour and facade for communicating with the pi coding agent.
  """

  alias LivePi.Config

  @type session_ref :: pid() | term()
  @type event :: map()
  @type session_options :: [
          browser_session_id: String.t(),
          project_path: String.t(),
          session_name: String.t() | nil,
          subscriber: pid()
        ]

  @callback start_session(session_options()) :: DynamicSupervisor.on_start_child()
  @callback subscribe(session_ref(), pid()) :: :ok | {:error, term()}
  @callback prompt(session_ref(), String.t(), keyword()) :: :ok | {:error, term()}
  @callback abort(session_ref()) :: :ok | {:error, term()}
  @callback new_session(session_ref(), keyword()) :: :ok | {:error, term()}
  @callback get_state(session_ref()) :: {:ok, map()} | {:error, term()}
  @callback get_messages(session_ref()) :: {:ok, [map()]} | {:error, term()}

  def start_session(opts) when is_list(opts) do
    impl().start_session(opts)
  end

  def subscribe(session_ref, subscriber \\ self()) do
    impl().subscribe(session_ref, subscriber)
  end

  def prompt(session_ref, message, opts \\ []) when is_binary(message) and is_list(opts) do
    impl().prompt(session_ref, message, opts)
  end

  def abort(session_ref) do
    impl().abort(session_ref)
  end

  def new_session(session_ref, opts \\ []) when is_list(opts) do
    impl().new_session(session_ref, opts)
  end

  def get_state(session_ref) do
    impl().get_state(session_ref)
  end

  def get_messages(session_ref) do
    impl().get_messages(session_ref)
  end

  def pi_executable do
    Config.pi_executable()
  end

  def pi_default_args do
    Config.pi_default_args()
  end

  defp impl do
    Config.pi_module()
  end
end
