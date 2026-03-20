defmodule LivePi.PiSession do
  @moduledoc false
  use GenServer, restart: :transient

  alias LivePi.PiTranscript

  require Logger

  defstruct [
    :project,
    :port,
    :buffer,
    :project_id,
    :session_id,
    :session_name,
    :session_file,
    :last_error,
    :pending,
    :transcript,
    :streaming,
    :compacting,
    :ready,
    :alive
  ]

  def child_spec(project) do
    %{
      id: {:pi_session, project.id},
      start: {__MODULE__, :start_link, [project]},
      restart: :transient
    }
  end

  def start_link(project) do
    GenServer.start_link(__MODULE__, project, name: via(project.id))
  end

  def via(project_id), do: {:via, Registry, {LivePi.PiSessionRegistry, project_id}}

  def snapshot(project_id) do
    GenServer.call(via(project_id), :snapshot)
  end

  def send_prompt(project_id, message) do
    GenServer.call(via(project_id), {:send_prompt, message}, 30_000)
  end

  @impl true
  def init(project) do
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      project: project,
      project_id: project.id,
      buffer: "",
      pending: %{},
      transcript: PiTranscript.new(),
      streaming: false,
      compacting: false,
      ready: false,
      alive: false
    }

    case open_port(project.path) do
      {:ok, port} ->
        send(self(), :bootstrap)
        {:ok, %{state | port: port, alive: true}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot_from_state(state), state}
  end

  def handle_call({:send_prompt, _message}, _from, %{alive: false} = state) do
    {:reply, {:error, "pi session is not running"}, state}
  end

  def handle_call({:send_prompt, _message}, _from, %{streaming: true} = state) do
    {:reply, {:error, "pi is still streaming a response"}, state}
  end

  def handle_call({:send_prompt, message}, from, state) do
    request_id = command_id("prompt")

    command = %{
      id: request_id,
      type: "prompt",
      message: message
    }

    state =
      state
      |> put_user_message(message)
      |> put_pending(request_id, from, :prompt)
      |> send_command(command)
      |> broadcast_snapshot()

    {:noreply, state}
  end

  @impl true
  def handle_info(:bootstrap, state) do
    state =
      state
      |> send_command(%{id: command_id("state"), type: "get_state"})
      |> send_command(%{id: command_id("messages"), type: "get_messages"})

    {:noreply, state}
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {:noreply, consume_data(state, data)}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("pi rpc session for #{state.project_id} exited with status #{status}")

    state =
      state
      |> fail_pending("pi session exited")
      |> Map.put(:alive, false)
      |> Map.put(:ready, false)
      |> Map.put(:streaming, false)
      |> Map.put(:compacting, false)
      |> Map.put(:last_error, "pi session exited with status #{status}")
      |> broadcast_snapshot()

    {:stop, {:port_exit, status}, state}
  end

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.warning("pi rpc session for #{state.project_id} terminated: #{inspect(reason)}")

    {:noreply,
     %{state | alive: false, ready: false, last_error: inspect(reason)} |> broadcast_snapshot()}
  end

  @impl true
  def terminate(_reason, state) do
    if state.port do
      Port.close(state.port)
    end

    :ok
  end

  defp open_port(cwd) do
    executable = Application.get_env(:live_pi, :pi_executable, "pi")
    args = Application.get_env(:live_pi, :pi_args, ["--mode", "rpc", "--no-session"])

    case System.find_executable(executable) do
      nil ->
        {:error, {:pi_not_found, executable}}

      path ->
        port =
          Port.open({:spawn_executable, path}, [
            :binary,
            :exit_status,
            :use_stdio,
            :stderr_to_stdout,
            {:args, args},
            {:cd, cwd}
          ])

        {:ok, port}
    end
  end

  defp consume_data(state, data) do
    buffer = state.buffer <> data
    {lines, rest} = split_lines(buffer, [])

    Enum.reduce(lines, %{state | buffer: rest}, fn line, acc ->
      line
      |> String.trim_trailing("\r")
      |> handle_line(acc)
    end)
  end

  defp split_lines(buffer, acc) do
    case :binary.match(buffer, "\n") do
      {index, 1} ->
        line = binary_part(buffer, 0, index)
        rest_start = index + 1
        rest = binary_part(buffer, rest_start, byte_size(buffer) - rest_start)
        split_lines(rest, [line | acc])

      :nomatch ->
        {Enum.reverse(acc), buffer}
    end
  end

  defp handle_line("", state), do: state

  defp handle_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"type" => "response"} = response} ->
        handle_response(state, response)

      {:ok, %{"type" => _type} = event} ->
        handle_event(state, event)

      {:error, error} ->
        Logger.warning("failed to decode pi rpc line: #{inspect(error)} line=#{inspect(line)}")
        state
    end
  end

  defp handle_response(state, %{"id" => id, "success" => false, "error" => error} = response) do
    state = reply_pending(state, id, {:error, error})

    state =
      case response["command"] do
        "prompt" -> %{state | streaming: false}
        _ -> state
      end

    %{state | last_error: error}
    |> broadcast_snapshot()
  end

  defp handle_response(state, %{"command" => "get_state", "data" => data, "id" => id}) do
    state =
      state
      |> reply_pending(id, {:ok, data})
      |> Map.put(:ready, true)
      |> Map.put(:alive, true)
      |> Map.put(:streaming, Map.get(data, "isStreaming", false))
      |> Map.put(:compacting, Map.get(data, "isCompacting", false))
      |> Map.put(:session_id, data["sessionId"])
      |> Map.put(:session_name, data["sessionName"])
      |> Map.put(:session_file, data["sessionFile"])
      |> Map.put(:last_error, nil)

    broadcast_snapshot(state)
  end

  defp handle_response(state, %{
         "command" => "get_messages",
         "data" => %{"messages" => messages},
         "id" => id
       }) do
    state =
      state
      |> reply_pending(id, {:ok, messages})
      |> Map.put(:transcript, PiTranscript.from_messages(messages))
      |> Map.put(:last_error, nil)

    broadcast_snapshot(state)
  end

  defp handle_response(state, %{"command" => "prompt", "id" => id}) do
    state
    |> reply_pending(id, :ok)
    |> Map.put(:last_error, nil)
    |> broadcast_snapshot()
  end

  defp handle_response(state, %{"id" => id} = _response) do
    state
    |> reply_pending(id, :ok)
    |> broadcast_snapshot()
  end

  defp handle_response(state, _response), do: state

  defp handle_event(state, event) do
    state =
      state
      |> update_stream_flags(event)
      |> Map.update!(:transcript, &PiTranscript.apply_event(&1, event))
      |> Map.put(:last_error, nil)

    broadcast_snapshot(state)
  end

  defp update_stream_flags(state, %{"type" => "agent_start"}), do: %{state | streaming: true}
  defp update_stream_flags(state, %{"type" => "agent_end"}), do: %{state | streaming: false}

  defp update_stream_flags(state, %{"type" => "auto_compaction_start"}),
    do: %{state | compacting: true}

  defp update_stream_flags(state, %{"type" => "auto_compaction_end"}),
    do: %{state | compacting: false}

  defp update_stream_flags(state, _event), do: state

  defp put_user_message(state, message) do
    timestamp = System.system_time(:millisecond)

    user_message = %{
      "role" => "user",
      "timestamp" => timestamp,
      "content" => message
    }

    update_in(state.transcript, &PiTranscript.put_message(&1, user_message))
  end

  defp send_command(%{port: port} = state, command) do
    payload = Jason.encode!(command) <> "\n"
    true = Port.command(port, payload)
    state
  end

  defp put_pending(state, id, from, command) do
    pending = Map.put(state.pending, id, %{from: from, command: command})
    %{state | pending: pending}
  end

  defp reply_pending(state, nil, _reply), do: state

  defp reply_pending(state, id, reply) do
    case Map.pop(state.pending, id) do
      {%{from: from}, pending} ->
        GenServer.reply(from, reply)
        %{state | pending: pending}

      {nil, _pending} ->
        state
    end
  end

  defp fail_pending(state, message) do
    Enum.each(state.pending, fn {_id, %{from: from}} ->
      GenServer.reply(from, {:error, message})
    end)

    %{state | pending: %{}}
  end

  defp broadcast_snapshot(state) do
    Phoenix.PubSub.broadcast(
      LivePi.PubSub,
      topic(state.project_id),
      {:pi_session_snapshot, state.project_id, snapshot_from_state(state)}
    )

    state
  end

  def topic(project_id), do: "pi_session:" <> project_id

  defp snapshot_from_state(state) do
    %{
      project_id: state.project_id,
      ready: state.ready,
      alive: state.alive,
      is_streaming: state.streaming,
      is_compacting: state.compacting,
      session_id: state.session_id,
      session_name: state.session_name,
      session_file: state.session_file,
      last_error: state.last_error,
      transcript_items: PiTranscript.items(state.transcript)
    }
  end

  defp command_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
