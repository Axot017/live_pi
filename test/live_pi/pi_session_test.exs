defmodule LivePi.PiSessionTest do
  use ExUnit.Case, async: false

  alias LivePi.PiSessions

  setup do
    project_root =
      Path.join(System.tmp_dir!(), "live-pi-session-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(project_root)

    script = Path.expand("../support/fake_pi_rpc.py", __DIR__)
    previous_exec = Application.get_env(:live_pi, :pi_executable)
    previous_args = Application.get_env(:live_pi, :pi_args)

    Application.put_env(:live_pi, :pi_executable, "python3")
    Application.put_env(:live_pi, :pi_args, [script])

    on_exit(fn ->
      Application.put_env(:live_pi, :pi_executable, previous_exec)
      Application.put_env(:live_pi, :pi_args, previous_args)
      File.rm_rf(project_root)
    end)

    project = %{id: "session-project", name: "session-project", path: project_root}

    {:ok, project: project}
  end

  test "reuses one worker per project and streams transcript items", %{project: project} do
    assert {:ok, pid} = PiSessions.ensure_started(project)
    assert {:ok, same_pid} = PiSessions.ensure_started(project)
    assert pid == same_pid

    project_id = project.id

    Phoenix.PubSub.subscribe(LivePi.PubSub, PiSessions.topic(project_id))

    assert_eventually(fn ->
      snapshot = PiSessions.snapshot(project_id)
      snapshot.ready and snapshot.alive
    end)

    assert :ok = PiSessions.send_prompt(project_id, "inspect the readme")

    assert_receive {:pi_session_snapshot, ^project_id, snapshot}, 5_000
    assert snapshot.alive

    assert_eventually(fn ->
      snapshot = PiSessions.snapshot(project.id)

      Enum.any?(snapshot.transcript_items, &(&1.kind == :assistant_turn)) and
        Enum.any?(snapshot.transcript_items, &(&1.kind == :tool_run)) and
        snapshot.is_streaming == false
    end)
  end

  defp assert_eventually(fun, attempts \\ 50)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      assert true
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(_fun, 0) do
    flunk("condition was not met in time")
  end
end
