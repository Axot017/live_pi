#!/usr/bin/env python3
import json
import sys
import time

state = {
    "messages": [],
    "session_id": "fake-session",
    "tool_call_id": "tool-call-1",
}


def emit(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


for raw_line in sys.stdin:
    line = raw_line.strip()
    if not line:
        continue

    command = json.loads(line)
    command_type = command.get("type")

    if command_type == "get_state":
        emit(
            {
                "id": command.get("id"),
                "type": "response",
                "command": "get_state",
                "success": True,
                "data": {
                    "model": None,
                    "thinkingLevel": "medium",
                    "isStreaming": False,
                    "isCompacting": False,
                    "steeringMode": "one-at-a-time",
                    "followUpMode": "one-at-a-time",
                    "sessionId": state["session_id"],
                    "autoCompactionEnabled": True,
                    "messageCount": len(state["messages"]),
                    "pendingMessageCount": 0,
                },
            }
        )
        continue

    if command_type == "get_messages":
        emit(
            {
                "id": command.get("id"),
                "type": "response",
                "command": "get_messages",
                "success": True,
                "data": {"messages": state["messages"]},
            }
        )
        continue

    if command_type == "prompt":
        now = int(time.time() * 1000)
        user_message = {"role": "user", "timestamp": now, "content": command.get("message", "")}
        assistant = {
            "role": "assistant",
            "timestamp": now + 1,
            "api": "fake",
            "provider": "fake",
            "model": "fake-model",
            "usage": {
                "input": 1,
                "output": 1,
                "cacheRead": 0,
                "cacheWrite": 0,
                "totalTokens": 2,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "total": 0},
            },
            "stopReason": "toolUse",
            "content": [
                {"type": "text", "text": "I checked the project."},
                {"type": "thinking", "thinking": "I should inspect the README first."},
                {
                    "type": "toolCall",
                    "id": state["tool_call_id"],
                    "name": "read",
                    "arguments": {"path": "README.md"},
                },
            ],
        }
        tool_result = {
            "role": "toolResult",
            "toolCallId": state["tool_call_id"],
            "toolName": "read",
            "content": [{"type": "text", "text": "# live_pi\nreal rpc test transcript"}],
            "details": {"bytes": 32},
            "isError": False,
            "timestamp": now + 2,
        }

        emit({"id": command.get("id"), "type": "response", "command": "prompt", "success": True})
        emit({"type": "agent_start"})
        emit({"type": "turn_start"})
        emit({"type": "message_start", "message": assistant})
        emit(
            {
                "type": "message_update",
                "message": assistant,
                "assistantMessageEvent": {
                    "type": "text_delta",
                    "contentIndex": 0,
                    "delta": "I checked the project.",
                    "partial": assistant,
                },
            }
        )
        emit(
            {
                "type": "message_update",
                "message": assistant,
                "assistantMessageEvent": {
                    "type": "thinking_delta",
                    "contentIndex": 1,
                    "delta": "I should inspect the README first.",
                    "partial": assistant,
                },
            }
        )
        emit(
            {
                "type": "message_update",
                "message": assistant,
                "assistantMessageEvent": {
                    "type": "toolcall_end",
                    "contentIndex": 2,
                    "toolCall": assistant["content"][2],
                    "partial": assistant,
                },
            }
        )
        emit(
            {
                "type": "tool_execution_start",
                "toolCallId": state["tool_call_id"],
                "toolName": "read",
                "args": {"path": "README.md"},
            }
        )
        emit(
            {
                "type": "tool_execution_update",
                "toolCallId": state["tool_call_id"],
                "toolName": "read",
                "args": {"path": "README.md"},
                "partialResult": {
                    "content": [{"type": "text", "text": "# live_pi"}],
                    "details": {"bytes": 10},
                },
            }
        )
        emit(
            {
                "type": "tool_execution_end",
                "toolCallId": state["tool_call_id"],
                "toolName": "read",
                "result": {
                    "content": [{"type": "text", "text": "# live_pi\nreal rpc test transcript"}],
                    "details": {"bytes": 32},
                },
                "isError": False,
            }
        )
        emit({"type": "message_end", "message": assistant})
        emit({"type": "turn_end", "message": assistant, "toolResults": [tool_result]})
        emit({"type": "agent_end", "messages": [assistant, tool_result]})

        state["messages"].extend([user_message, assistant, tool_result])
        continue

    emit(
        {
            "id": command.get("id"),
            "type": "response",
            "command": command_type,
            "success": False,
            "error": "unsupported",
        }
    )
