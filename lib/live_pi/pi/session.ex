defmodule LivePi.Pi.Session do
  @moduledoc """
  Default pi implementation.

  Phase 1 only wires the public contract and supervision target.
  Phase 2 will add the JSONL RPC transport over a Port.
  """

  use GenServer

  @behaviour LivePi.Pi

  alias LivePi.Pi.SessionSupervisor

  defstruct [:browser_session_id, :project_path, :session_name, subscribers: MapSet.new()]

  @type state :: %__MODULE__{
          browser_session_id: String.t() | nil,
          project_path: String.t() | nil,
          session_name: String.t() | nil,
          subscribers: MapSet.t(pid())
        }

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.take(opts, [:browser_session_id, :project_path])},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl LivePi.Pi
  def start_session(opts) do
    DynamicSupervisor.start_child(SessionSupervisor, {__MODULE__, opts})
  end

  @impl LivePi.Pi
  def subscribe(session_ref, subscriber) do
    GenServer.call(session_ref, {:subscribe, subscriber})
  end

  @impl LivePi.Pi
  def prompt(_session_ref, _message, _opts) do
    {:error, :not_implemented}
  end

  @impl LivePi.Pi
  def abort(_session_ref) do
    {:error, :not_implemented}
  end

  @impl LivePi.Pi
  def new_session(_session_ref, _opts) do
    {:error, :not_implemented}
  end

  @impl LivePi.Pi
  def get_state(_session_ref) do
    {:ok, %{status: :idle, transport: :uninitialized}}
  end

  @impl LivePi.Pi
  def get_messages(_session_ref) do
    {:ok, []}
  end

  @impl true
  def init(opts) do
    subscribers = initial_subscribers(opts)
    Enum.each(subscribers, &Process.monitor/1)

    state = %__MODULE__{
      browser_session_id: Keyword.get(opts, :browser_session_id),
      project_path: Keyword.get(opts, :project_path),
      session_name: Keyword.get(opts, :session_name),
      subscribers: subscribers
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, subscriber}, _from, state) do
    Process.monitor(subscriber)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, subscriber)}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  defp initial_subscribers(opts) do
    case Keyword.get(opts, :subscriber) do
      nil -> MapSet.new()
      pid -> MapSet.new([pid])
    end
  end
end
