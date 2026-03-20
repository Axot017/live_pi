defmodule LivePi.PiTranscript do
  @moduledoc false

  @type transcript_state :: %{
          items: %{optional(String.t()) => map()},
          order: [String.t()],
          event_seq: non_neg_integer()
        }

  def new do
    %{items: %{}, order: [], event_seq: 0}
  end

  def from_messages(messages) when is_list(messages) do
    Enum.reduce(messages, new(), &put_message(&2, &1))
  end

  def items(state) do
    state.order
    |> Enum.map(&Map.fetch!(state.items, &1))
  end

  def put_message(state, %{"role" => role} = message) do
    case role do
      "user" ->
        put_item(state, user_item(message))

      "assistant" ->
        put_item(state, assistant_item(message))

      "toolResult" ->
        put_item(state, tool_result_item(message))

      "bashExecution" ->
        put_item(state, bash_execution_item(message))

      "custom" ->
        put_item(state, custom_item(message))

      "branchSummary" ->
        put_item(state, summary_item(message, "branch summary", Map.get(message, "summary", "")))

      "compactionSummary" ->
        put_item(
          state,
          summary_item(message, "compaction summary", Map.get(message, "summary", ""))
        )

      _ ->
        state
    end
  end

  def put_message(state, _message), do: state

  def apply_event(state, %{"type" => "message_start", "message" => message}) do
    put_message(state, message)
  end

  def apply_event(state, %{"type" => "message_update", "assistantMessageEvent" => event}) do
    partial = Map.get(event, "partial") || %{}
    put_item(state, assistant_item(partial))
  end

  def apply_event(state, %{"type" => "message_end", "message" => message}) do
    put_message(state, message)
  end

  def apply_event(state, %{"type" => "tool_execution_start"} = event) do
    put_item(state, tool_event_item(event, :running))
  end

  def apply_event(state, %{"type" => "tool_execution_update"} = event) do
    put_item(state, tool_event_item(event, :running))
  end

  def apply_event(state, %{"type" => "tool_execution_end"} = event) do
    put_item(state, tool_event_item(event, if(event["isError"], do: :error, else: :ok)))
  end

  def apply_event(state, %{"type" => type} = event)
      when type in [
             "agent_start",
             "agent_end",
             "turn_start",
             "turn_end",
             "auto_compaction_start",
             "auto_compaction_end",
             "auto_retry_start",
             "auto_retry_end",
             "extension_error"
           ] do
    put_event_notice(state, event)
  end

  def apply_event(state, _event), do: state

  defp put_event_notice(state, event) do
    seq = state.event_seq + 1
    id = "event-#{seq}"

    item = %{
      id: id,
      kind: :system_notice,
      at: now_label(),
      title: event_title(event),
      body: event_body(event)
    }

    %{state | event_seq: seq}
    |> put_item(item)
  end

  defp user_item(message) do
    %{
      id: message_id(message),
      kind: :user_message,
      author: "you",
      at: timestamp_label(message["timestamp"]),
      body: text_from_content(message["content"])
    }
  end

  defp assistant_item(message) do
    blocks =
      message
      |> Map.get("content", [])
      |> Enum.with_index()
      |> Enum.map(fn {content, index} ->
        base = %{id: "#{message_id(message)}-block-#{index}"}

        case content do
          %{"type" => "text", "text" => text} ->
            Map.merge(base, %{kind: :text, text: text})

          %{"type" => "thinking"} = thinking ->
            Map.merge(base, %{kind: :thinking, text: Map.get(thinking, "thinking", "")})

          %{"type" => "toolCall"} = tool_call ->
            Map.merge(base, %{
              kind: :tool_call,
              tool_call_id: Map.get(tool_call, "id"),
              name: Map.get(tool_call, "name", "tool"),
              arguments: encode_json(Map.get(tool_call, "arguments", %{}))
            })

          other ->
            Map.merge(base, %{kind: :text, text: encode_json(other)})
        end
      end)

    %{
      id: message_id(message),
      kind: :assistant_turn,
      author: "pi",
      at: timestamp_label(message["timestamp"]),
      blocks: blocks
    }
  end

  defp tool_result_item(message) do
    tool_call_id = message["toolCallId"] || message_id(message)

    %{
      id: tool_id(tool_call_id),
      kind: :tool_run,
      tool_call_id: tool_call_id,
      tool_name: message["toolName"] || "tool",
      status: if(message["isError"], do: :error, else: :ok),
      summary: nil,
      output: text_from_content(message["content"]),
      meta: normalize_meta(message["details"])
    }
  end

  defp bash_execution_item(message) do
    %{
      id: message_id(message),
      kind: :tool_run,
      tool_name: "bash",
      status:
        if(message["cancelled"] || is_nil(message["exitCode"]) || message["exitCode"] != 0,
          do: :error,
          else: :ok
        ),
      summary: Map.get(message, "command"),
      output: Map.get(message, "output", ""),
      meta:
        normalize_meta(%{
          exit_code: Map.get(message, "exitCode"),
          truncated: Map.get(message, "truncated"),
          full_output_path: Map.get(message, "fullOutputPath")
        })
    }
  end

  defp custom_item(message) do
    %{
      id: message_id(message),
      kind: :system_notice,
      at: timestamp_label(message["timestamp"]),
      title: Map.get(message, "customType", "custom"),
      body: text_from_content(message["content"])
    }
  end

  defp summary_item(message, title, body) do
    %{
      id: message_id(message),
      kind: :system_notice,
      at: timestamp_label(message["timestamp"]),
      title: title,
      body: body
    }
  end

  defp tool_event_item(event, status) do
    tool_call_id = event["toolCallId"] || "unknown"
    result = event["result"] || event["partialResult"] || %{}

    %{
      id: tool_id(tool_call_id),
      kind: :tool_run,
      tool_call_id: tool_call_id,
      tool_name: event["toolName"] || "tool",
      status: status,
      summary: event_summary(event),
      output: text_from_content(result["content"]),
      meta: normalize_meta(result["details"] || event["args"])
    }
  end

  defp put_item(state, %{id: id} = item) do
    order = if Map.has_key?(state.items, id), do: state.order, else: state.order ++ [id]
    %{state | items: Map.put(state.items, id, item), order: order}
  end

  defp message_id(message) do
    role = Map.get(message, "role", "message")
    timestamp = Map.get(message, "timestamp", 0)
    "#{role}-#{timestamp}"
  end

  defp tool_id(id), do: "tool-#{id}"

  defp event_summary(%{"args" => args}) when args in [%{}, nil], do: nil
  defp event_summary(%{"args" => args}), do: encode_json(args)
  defp event_summary(_event), do: nil

  defp text_from_content(content) when is_binary(content), do: content

  defp text_from_content(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      %{"type" => "image"} -> "[image]"
      other -> encode_json(other)
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp text_from_content(_), do: ""

  defp normalize_meta(nil), do: nil

  defp normalize_meta(meta) when is_map(meta) do
    meta
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Enum.map(fn {key, value} -> {to_string(key), meta_value(value)} end)
    |> case do
      [] -> nil
      pairs -> Map.new(pairs)
    end
  end

  defp normalize_meta(_), do: nil

  defp meta_value(value) when is_binary(value), do: value
  defp meta_value(value) when is_number(value), do: to_string(value)
  defp meta_value(value) when is_boolean(value), do: to_string(value)
  defp meta_value(value), do: encode_json(value)

  defp event_title(%{"type" => type}), do: String.replace(type, "_", " ")

  defp event_body(%{"type" => "agent_end", "messages" => messages}) do
    "completed with #{length(messages)} message(s) in this run"
  end

  defp event_body(%{"type" => "turn_end", "toolResults" => results}) do
    "turn finished with #{length(results)} tool result(s)"
  end

  defp event_body(%{"type" => "auto_compaction_start", "reason" => reason}),
    do: "reason: #{reason}"

  defp event_body(%{"type" => "auto_compaction_end", "errorMessage" => error}),
    do: error || "compaction finished"

  defp event_body(%{"type" => "auto_retry_start"} = event),
    do: Map.get(event, "errorMessage", "retrying")

  defp event_body(%{"type" => "auto_retry_end", "finalError" => error}),
    do: error || "retry finished"

  defp event_body(%{"type" => "extension_error", "error" => error}), do: error
  defp event_body(_event), do: ""

  defp timestamp_label(timestamp) when is_number(timestamp) do
    timestamp
    |> trunc()
    |> DateTime.from_unix(:millisecond)
    |> case do
      {:ok, datetime} -> Calendar.strftime(datetime, "%H:%M:%S")
      _ -> now_label()
    end
  end

  defp timestamp_label(_), do: now_label()

  defp now_label do
    Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
  end

  defp encode_json(value) do
    Jason.encode!(value, pretty: true)
  rescue
    _ -> inspect(value)
  end
end
