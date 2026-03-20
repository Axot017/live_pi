#!/usr/bin/env elixir
Mix.install([{:jason, "~> 1.4"}])

state = %{messages: [], session_id: "fake-session", tool_call_id: "tool-call-1"}

emit = fn payload ->
  IO.write(Jason.encode!(payload))
  IO.write("\n")
end

text = fn value -> [%{"type" => "text", "text" => value}] end

assistant_message = fn timestamp, text_value, thinking_value, tool_call_id ->
  %{
    "role" => "assistant",
    "timestamp" => timestamp,
    "api" => "fake",
    "provider" => "fake",
    "model" => "fake-model",
    "usage" => %{
      "input" => 1,
      "output" => 1,
      "cacheRead" => 0,
      "cacheWrite" => 0,
      "totalTokens" => 2,
      "cost" => %{"input" => 0, "output" => 0, "cacheRead" => 0, "cacheWrite" => 0, "total" => 0}
    },
    "stopReason" => "toolUse",
    "content" => [
      %{"type" => "text", "text" => text_value},
      %{"type" => "thinking", "thinking" => thinking_value},
      %{
        "type" => "toolCall",
        "id" => tool_call_id,
        "name" => "read",
        "arguments" => %{"path" => "README.md"}
      }
    ]
  }
end

loop = fn loop, state ->
  case IO.read(:line) do
    :eof ->
      :ok

    line ->
      line = String.trim(line)

      if line != "" do
        command = Jason.decode!(line)

        case command["type"] do
          "get_state" ->
            emit.(%{
              "id" => command["id"],
              "type" => "response",
              "command" => "get_state",
              "success" => true,
              "data" => %{
                "model" => nil,
                "thinkingLevel" => "medium",
                "isStreaming" => false,
                "isCompacting" => false,
                "steeringMode" => "one-at-a-time",
                "followUpMode" => "one-at-a-time",
                "sessionId" => state.session_id,
                "autoCompactionEnabled" => true,
                "messageCount" => length(state.messages),
                "pendingMessageCount" => 0
              }
            })

            loop.(loop, state)

          "get_messages" ->
            emit.(%{
              "id" => command["id"],
              "type" => "response",
              "command" => "get_messages",
              "success" => true,
              "data" => %{"messages" => state.messages}
            })

            loop.(loop, state)

          "prompt" ->
            now = System.system_time(:millisecond)

            user_message = %{
              "role" => "user",
              "timestamp" => now,
              "content" => command["message"]
            }

            assistant =
              assistant_message.(
                now + 1,
                "I checked the project.",
                "I should inspect the README first.",
                state.tool_call_id
              )

            tool_result = %{
              "role" => "toolResult",
              "toolCallId" => state.tool_call_id,
              "toolName" => "read",
              "content" => text.("# live_pi\nreal rpc test transcript"),
              "details" => %{"bytes" => 32},
              "isError" => false,
              "timestamp" => now + 2
            }

            emit.(%{
              "id" => command["id"],
              "type" => "response",
              "command" => "prompt",
              "success" => true
            })

            emit.(%{"type" => "agent_start"})
            emit.(%{"type" => "turn_start"})
            emit.(%{"type" => "message_start", "message" => assistant})

            emit.(%{
              "type" => "message_update",
              "message" => assistant,
              "assistantMessageEvent" => %{
                "type" => "text_delta",
                "contentIndex" => 0,
                "delta" => "I checked the project.",
                "partial" => assistant
              }
            })

            emit.(%{
              "type" => "message_update",
              "message" => assistant,
              "assistantMessageEvent" => %{
                "type" => "thinking_delta",
                "contentIndex" => 1,
                "delta" => "I should inspect the README first.",
                "partial" => assistant
              }
            })

            emit.(%{
              "type" => "message_update",
              "message" => assistant,
              "assistantMessageEvent" => %{
                "type" => "toolcall_end",
                "contentIndex" => 2,
                "toolCall" => Enum.at(assistant["content"], 2),
                "partial" => assistant
              }
            })

            emit.(%{
              "type" => "tool_execution_start",
              "toolCallId" => state.tool_call_id,
              "toolName" => "read",
              "args" => %{"path" => "README.md"}
            })

            emit.(%{
              "type" => "tool_execution_update",
              "toolCallId" => state.tool_call_id,
              "toolName" => "read",
              "args" => %{"path" => "README.md"},
              "partialResult" => %{"content" => text.("# live_pi"), "details" => %{"bytes" => 10}}
            })

            emit.(%{
              "type" => "tool_execution_end",
              "toolCallId" => state.tool_call_id,
              "toolName" => "read",
              "result" => %{
                "content" => text.("# live_pi\nreal rpc test transcript"),
                "details" => %{"bytes" => 32}
              },
              "isError" => false
            })

            emit.(%{"type" => "message_end", "message" => assistant})
            emit.(%{"type" => "turn_end", "message" => assistant, "toolResults" => [tool_result]})
            emit.(%{"type" => "agent_end", "messages" => [assistant, tool_result]})

            loop.(loop, %{
              state
              | messages: state.messages ++ [user_message, assistant, tool_result]
            })

          _ ->
            emit.(%{
              "id" => command["id"],
              "type" => "response",
              "command" => command["type"],
              "success" => false,
              "error" => "unsupported"
            })

            loop.(loop, state)
        end
      else
        loop.(loop, state)
      end
  end
end

loop.(loop, state)
