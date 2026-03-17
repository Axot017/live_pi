defmodule LivePi.Pi.Session do
  @moduledoc """
  Port-backed pi RPC session process.
  """

  use GenServer

  @behaviour LivePi.Pi

  alias LivePi.Pi
  alias LivePi.Pi.RPC
  alias LivePi.Pi.SessionSupervisor

  @call_timeout 15_000

  defstruct [
    :browser_session_id,
    :project_path,
    :session_name,
    :port,
    :buffer,
    :next_id,
    :is_streaming,
    :remote_state,
    :messages,
    subscribers: MapSet.new(),
    pending: %{}
  ]

  @type state :: %__MODULE__{
          browser_session_id: String.t() | nil,
          project_path: String.t() | nil,
          session_name: String.t() | nil,
          port: port() | nil,
          buffer: String.t(),
          next_id: non_neg_integer(),
          is_streaming: boolean(),
          remote_state: map(),
          messages: [map()],
          subscribers: MapSet.t(pid()),
          pending: %{optional(String.t()) => {GenServer.from(), String.t()}}
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
    GenServer.call(session_ref, {:subscribe, subscriber}, @call_timeout)
  end

  @impl LivePi.Pi
  def prompt(session_ref, message, opts) do
    GenServer.call(session_ref, {:prompt, message, opts}, @call_timeout)
  end

  @impl LivePi.Pi
  def abort(session_ref) do
    GenServer.call(session_ref, :abort, @call_timeout)
  end

  @impl LivePi.Pi
  def new_session(session_ref, opts) do
    GenServer.call(session_ref, {:new_session, opts}, @call_timeout)
  end

  @impl LivePi.Pi
  def get_state(session_ref) do
    GenServer.call(session_ref, :get_state, @call_timeout)
  end

  @impl LivePi.Pi
  def get_messages(session_ref) do
    GenServer.call(session_ref, :get_messages, @call_timeout)
  end

  @impl true
  def init(opts) do
    subscribers = initial_subscribers(opts)
    Enum.each(subscribers, &Process.monitor/1)

    with {:ok, port} <- open_port(opts) do
      state = %__MODULE__{
        browser_session_id: Keyword.get(opts, :browser_session_id),
        project_path: Keyword.get(opts, :project_path),
        session_name: Keyword.get(opts, :session_name),
        port: port,
        buffer: "",
        next_id: 1,
        is_streaming: false,
        remote_state: %{"isStreaming" => false},
        messages: [],
        subscribers: subscribers,
        pending: %{}
      }

      {:ok, state, {:continue, :post_start_setup}}
    end
  end

  @impl true
  def handle_continue(:post_start_setup, state) do
    state = maybe_set_session_name(state)
    {:noreply, state}
  end

  @impl true
  def handle_call({:subscribe, subscriber}, _from, state) do
    Process.monitor(subscriber)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, subscriber)}}
  end

  def handle_call({:prompt, message, opts}, from, state) do
    payload =
      %{"type" => "prompt", "message" => message}
      |> maybe_put("streamingBehavior", Keyword.get(opts, :streaming_behavior))

    {:noreply, send_command(state, from, "prompt", payload)}
  end

  def handle_call(:abort, from, state) do
    {:noreply, send_command(state, from, "abort", %{"type" => "abort"})}
  end

  def handle_call({:new_session, opts}, from, state) do
    payload =
      %{"type" => "new_session"}
      |> maybe_put("parentSession", Keyword.get(opts, :parent_session))

    {:noreply, send_command(state, from, "new_session", payload)}
  end

  def handle_call(:get_state, from, state) do
    {:noreply, send_command(state, from, "get_state", %{"type" => "get_state"})}
  end

  def handle_call(:get_messages, from, state) do
    {:noreply, send_command(state, from, "get_messages", %{"type" => "get_messages"})}
  end

  @impl true
  def handle_info({port, {:data, chunk}}, %{port: port} = state) when is_binary(chunk) do
    {decoded_messages, buffer} = RPC.decode_chunk(state.buffer, chunk)

    state =
      Enum.reduce(decoded_messages, %{state | buffer: buffer}, fn
        {:ok, message}, acc ->
          handle_rpc_message(acc, message)

        {:error, {:invalid_json, line, reason}}, acc ->
          notify(
            acc,
            {:pi_event, self(), %{type: "rpc_parse_error", line: line, reason: inspect(reason)}}
          )

          acc
      end)

    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    reason = {:port_exit, status}

    Enum.each(state.pending, fn {_id, {from, _command}} ->
      GenServer.reply(from, {:error, reason})
    end)

    notify(state, {:pi_exit, self(), reason})
    {:stop, reason, %{state | pending: %{}, port: nil}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  defp open_port(opts) do
    executable = Keyword.get(opts, :pi_executable, Pi.pi_executable())
    args = Keyword.get(opts, :pi_args, default_pi_args())
    cwd = Keyword.fetch!(opts, :project_path)

    case resolve_executable(executable) do
      nil ->
        {:stop, {:pi_executable_not_found, executable}}

      resolved ->
        port =
          Port.open({:spawn_executable, resolved}, [
            :binary,
            :exit_status,
            :use_stdio,
            :stderr_to_stdout,
            :hide,
            args: args,
            cd: cwd
          ])

        {:ok, port}
    end
  rescue
    error in ArgumentError -> {:stop, {:pi_port_open_failed, Exception.message(error)}}
  end

  defp resolve_executable(executable) do
    cond do
      String.contains?(executable, "/") and File.exists?(executable) -> executable
      true -> System.find_executable(executable)
    end
  end

  defp default_pi_args do
    ["--mode", "rpc", "--no-session" | Pi.pi_default_args()]
  end

  defp maybe_set_session_name(%{session_name: nil} = state), do: state

  defp maybe_set_session_name(state) do
    payload = %{
      "type" => "set_session_name",
      "name" => state.session_name
    }

    send_payload(state, payload)
  end

  defp send_command(state, from, command, payload) do
    id = next_id(state)
    payload = Map.put(payload, "id", id)

    state
    |> put_pending(id, from, command)
    |> send_payload(payload)
  end

  defp put_pending(state, id, from, command) do
    %{state | pending: Map.put(state.pending, id, {from, command}), next_id: state.next_id + 1}
  end

  defp send_payload(state, payload) do
    true = Port.command(state.port, RPC.encode!(payload))
    state
  end

  defp next_id(state) do
    Integer.to_string(state.next_id)
  end

  defp handle_rpc_message(state, %{"type" => "response", "id" => id} = response) do
    case Map.pop(state.pending, id) do
      {nil, pending} ->
        %{state | pending: pending}

      {{from, command}, pending} ->
        state = %{state | pending: pending}
        {state, reply} = apply_response(state, command, response)
        GenServer.reply(from, reply)
        state
    end
  end

  defp handle_rpc_message(state, %{"type" => "response"} = response) do
    case response do
      %{"command" => "set_session_name", "success" => false, "error" => error} ->
        notify(state, {:pi_event, self(), %{type: "session_name_error", error: error}})

      _ ->
        :ok
    end

    state
  end

  defp handle_rpc_message(state, %{"type" => event_type} = event) do
    state = update_state_from_event(state, event_type, event)
    notify(state, {:pi_event, self(), event})
    state
  end

  defp apply_response(state, command, %{"success" => false, "error" => error}) do
    notify(state, {:pi_event, self(), %{type: "rpc_error", command: command, error: error}})
    {state, {:error, error}}
  end

  defp apply_response(state, "get_state", %{"success" => true, "data" => data}) do
    remote_state =
      state.remote_state
      |> Map.merge(data)
      |> Map.put("isStreaming", state.is_streaming)

    {%{state | remote_state: remote_state}, {:ok, remote_state}}
  end

  defp apply_response(state, "get_messages", %{
         "success" => true,
         "data" => %{"messages" => messages}
       }) do
    messages = messages || state.messages
    {%{state | messages: messages}, {:ok, messages}}
  end

  defp apply_response(state, _command, %{"success" => true}) do
    {state, :ok}
  end

  defp apply_response(state, _command, response) do
    {state, {:ok, Map.get(response, "data")}}
  end

  defp update_state_from_event(state, "agent_start", _event) do
    put_remote_streaming(state, true)
  end

  defp update_state_from_event(state, "agent_end", %{"messages" => messages})
       when is_list(messages) do
    state
    |> put_remote_streaming(false)
    |> Map.put(:messages, messages)
  end

  defp update_state_from_event(state, "agent_end", _event) do
    put_remote_streaming(state, false)
  end

  defp update_state_from_event(state, "message_end", %{"message" => message}) do
    %{state | messages: upsert_message(state.messages, message)}
  end

  defp update_state_from_event(state, "message_update", _event) do
    put_remote_streaming(state, true)
  end

  defp update_state_from_event(state, _type, _event), do: state

  defp put_remote_streaming(state, value) do
    %{
      state
      | is_streaming: value,
        remote_state: Map.put(state.remote_state, "isStreaming", value)
    }
  end

  defp upsert_message(messages, %{"timestamp" => timestamp} = message) do
    if Enum.any?(messages, &(&1["timestamp"] == timestamp and &1["role"] == message["role"])) do
      Enum.map(messages, fn existing ->
        if existing["timestamp"] == timestamp and existing["role"] == message["role"] do
          message
        else
          existing
        end
      end)
    else
      messages ++ [message]
    end
  end

  defp upsert_message(messages, message), do: messages ++ [message]

  defp notify(state, message) do
    Enum.each(state.subscribers, &send(&1, message))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp initial_subscribers(opts) do
    case Keyword.get(opts, :subscriber) do
      nil -> MapSet.new()
      pid -> MapSet.new([pid])
    end
  end
end
