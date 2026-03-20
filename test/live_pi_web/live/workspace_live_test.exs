defmodule LivePiWeb.WorkspaceLiveTest do
  use LivePiWeb.ConnCase, async: false

  setup do
    root =
      Path.join(System.tmp_dir!(), "live-pi-workspace-test-#{System.unique_integer([:positive])}")

    project_path = Path.join(root, "demo-project")
    File.mkdir_p!(project_path)

    script = Path.expand("../../support/fake_pi_rpc.py", __DIR__)
    previous_root = Application.get_env(:live_pi, :projects_root)
    previous_exec = Application.get_env(:live_pi, :pi_executable)
    previous_args = Application.get_env(:live_pi, :pi_args)

    Application.put_env(:live_pi, :projects_root, root)
    Application.put_env(:live_pi, :pi_executable, "python3")
    Application.put_env(:live_pi, :pi_args, [script])

    on_exit(fn ->
      Application.put_env(:live_pi, :projects_root, previous_root)
      Application.put_env(:live_pi, :pi_executable, previous_exec)
      Application.put_env(:live_pi, :pi_args, previous_args)
      File.rm_rf(root)
    end)

    :ok
  end

  test "sends a message and renders assistant thinking and tool output", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "demo-project"

    view
    |> form("#chat-composer", %{message: "inspect readme"})
    |> render_change()

    view
    |> form("#chat-composer", %{message: "inspect readme"})
    |> render_submit()

    assert_eventually(fn ->
      rendered = render(view)

      rendered =~ "I checked the project." and rendered =~ "tool" and rendered =~ "thinking"
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
