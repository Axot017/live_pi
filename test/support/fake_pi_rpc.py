#!/usr/bin/env python3
import json
import sys

state = {
    "is_streaming": False,
    "messages": [],
    "session_name": None,
    "session_id": "fake-session",
    "session_file": "/tmp/fake-session.jsonl",
}


def send(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def user_message(text):
    return {
        "role": "user",
        "content": text,
        "timestamp": 1000 + len(state["messages"]),
        "attachments": [],
    }


def assistant_message(text):
    return {
        "role": "assistant",
        "content": [{"type": "text", "text": text}],
        "timestamp": 2000 + len(state["messages"]),
        "provider": "fake",
        "model": "fake-model",
    }


for raw in sys.stdin:
    line = raw.rstrip("\n")
    if not line:
        continue

    command = json.loads(line)
    command_type = command.get("type")
    request_id = command.get("id")

    if command_type == "set_session_name":
        state["session_name"] = command.get("name")
        send({"type": "response", "command": "set_session_name", "success": True})
    elif command_type == "get_state":
        send(
            {
                "id": request_id,
                "type": "response",
                "command": "get_state",
                "success": True,
                "data": {
                    "isStreaming": state["is_streaming"],
                    "sessionId": state["session_id"],
                    "sessionFile": state["session_file"],
                    "sessionName": state["session_name"],
                    "messageCount": len(state["messages"]),
                    "pendingMessageCount": 0,
                },
            }
        )
    elif command_type == "get_messages":
        send(
            {
                "id": request_id,
                "type": "response",
                "command": "get_messages",
                "success": True,
                "data": {"messages": state["messages"]},
            }
        )
    elif command_type == "new_session":
        state["messages"] = []
        state["is_streaming"] = False
        send(
            {
                "id": request_id,
                "type": "response",
                "command": "new_session",
                "success": True,
                "data": {"cancelled": False},
            }
        )
    elif command_type == "abort":
        state["is_streaming"] = False
        send({"id": request_id, "type": "response", "command": "abort", "success": True})
    elif command_type == "prompt":
        message_text = command.get("message", "")
        if message_text == "cause-error":
            send(
                {
                    "id": request_id,
                    "type": "response",
                    "command": "prompt",
                    "success": False,
                    "error": "prompt failed",
                }
            )
            continue
        if message_text == "emit-invalid-json":
            sys.stdout.write("not-json\n")
            sys.stdout.flush()

        send({"id": request_id, "type": "response", "command": "prompt", "success": True})

        user = user_message(message_text)
        assistant = assistant_message(f"Echo: {message_text}")

        state["is_streaming"] = True
        send({"type": "agent_start"})
        send({"type": "message_start", "message": assistant})
        send(
            {
                "type": "message_update",
                "message": assistant,
                "assistantMessageEvent": {
                    "type": "text_delta",
                    "contentIndex": 0,
                    "delta": "Echo: ",
                    "partial": assistant,
                },
            }
        )
        send(
            {
                "type": "message_update",
                "message": assistant,
                "assistantMessageEvent": {
                    "type": "text_delta",
                    "contentIndex": 0,
                    "delta": message_text,
                    "partial": assistant,
                },
            }
        )
        send({"type": "message_end", "message": assistant})

        state["messages"] = state["messages"] + [user, assistant]
        state["is_streaming"] = False
        send({"type": "agent_end", "messages": state["messages"]})
    else:
        send(
            {
                "id": request_id,
                "type": "response",
                "command": command_type,
                "success": False,
                "error": f"unsupported command: {command_type}",
            }
        )
