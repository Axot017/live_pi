defmodule LivePi.Pi.SessionTest do
  use ExUnit.Case, async: false

  alias LivePi.Pi.Session

  setup do
    project_dir =
      Path.join(System.tmp_dir!(), "live-pi-session-#{System.unique_integer([:positive])}")

    File.mkdir_p!(project_dir)

    on_exit(fn ->
      File.rm_rf!(project_dir)
    end)

    {:ok,
     project_dir: project_dir, script_path: Path.expand("../../support/fake_pi_rpc.py", __DIR__)}
  end

  test "start_link starts port-backed session and get_state/1 returns remote state", %{
    project_dir: project_dir,
    script_path: script_path
  } do
    session = start_session!(project_dir, script_path, session_name: "workspace")

    _ = :sys.get_state(session)

    assert {:ok, state} = Session.get_state(session)
    assert state["sessionId"] == "fake-session"
    assert state["sessionName"] == "workspace"
    assert state["isStreaming"] == false
  end

  test "prompt/3 emits streaming events and get_messages/1 returns transcript", %{
    project_dir: project_dir,
    script_path: script_path
  } do
    session = start_session!(project_dir, script_path)

    assert :ok = Session.prompt(session, "hello", [])

    assert_receive {:pi_event, ^session, %{"type" => "agent_start"}}

    assert_receive {:pi_event, ^session,
                    %{
                      "type" => "message_update",
                      "assistantMessageEvent" => %{"type" => "text_delta", "delta" => "Echo: "}
                    }}

    assert_receive {:pi_event, ^session, %{"type" => "agent_end", "messages" => messages}}
    assert length(messages) == 2

    assert {:ok, remote_state} = Session.get_state(session)
    assert remote_state["isStreaming"] == false
    assert remote_state["messageCount"] == 2

    assert {:ok, transcript} = Session.get_messages(session)
    assert Enum.map(transcript, & &1["role"]) == ["user", "assistant"]
  end

  test "prompt/3 returns rpc errors and notifies subscribers", %{
    project_dir: project_dir,
    script_path: script_path
  } do
    session = start_session!(project_dir, script_path)

    assert {:error, "prompt failed"} = Session.prompt(session, "cause-error", [])

    assert_receive {:pi_event, ^session,
                    %{type: "rpc_error", command: "prompt", error: "prompt failed"}}
  end

  test "invalid rpc output is surfaced as parse error event", %{
    project_dir: project_dir,
    script_path: script_path
  } do
    session = start_session!(project_dir, script_path)

    assert :ok = Session.prompt(session, "emit-invalid-json", [])

    assert_receive {:pi_event, ^session, %{type: "rpc_parse_error", line: "not-json"}}, 1_000
  end

  test "new_session/2 resets remote transcript", %{
    project_dir: project_dir,
    script_path: script_path
  } do
    session = start_session!(project_dir, script_path)

    assert :ok = Session.prompt(session, "hello", [])
    assert_receive {:pi_event, ^session, %{"type" => "agent_end"}}

    assert :ok = Session.new_session(session, [])
    assert {:ok, transcript} = Session.get_messages(session)
    assert transcript == []
  end

  test "abort/1 acknowledges abort command", %{project_dir: project_dir, script_path: script_path} do
    session = start_session!(project_dir, script_path)

    assert :ok = Session.abort(session)
  end

  test "start_link returns an error when the pi executable cannot be found", %{
    project_dir: project_dir
  } do
    Process.flag(:trap_exit, true)

    assert {:error, {:pi_executable_not_found, "missing-pi"}} =
             Session.start_link(
               browser_session_id: "browser",
               project_path: project_dir,
               subscriber: self(),
               pi_executable: "missing-pi",
               pi_args: []
             )
  end

  defp start_session!(project_dir, script_path, opts \\ []) do
    python = System.find_executable("python3")

    start_supervised!({
      Session,
      Keyword.merge(opts,
        browser_session_id: "browser-session",
        project_path: project_dir,
        subscriber: self(),
        pi_executable: python,
        pi_args: [script_path]
      )
    })
  end
end
