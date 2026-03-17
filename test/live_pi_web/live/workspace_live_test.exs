defmodule LivePiWeb.WorkspaceLiveTest do
  use LivePiWeb.LiveViewCase, async: false

  import Mox

  alias LivePi.Projects.Project

  setup :verify_on_exit!

  test "renders empty workspace state", %{conn: conn} do
    expect(LivePi.ProjectsMock, :list_projects, 2, fn -> [] end)

    expect(LivePi.ProjectsMock, :browse, 2, fn nil ->
      {:ok,
       %{current_path: "/srv/projects", root_path: "/srv/projects", parent_path: nil, entries: []}}
    end)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Connected workspaces"
    assert html =~ "No projects discovered yet"
    assert html =~ "Select a project and send your first prompt"
  end

  test "selecting a project enables chat and loads transcript", %{conn: conn} do
    project = project_fixture()
    session_ref = start_supervised!({Task, fn -> Process.sleep(:infinity) end})

    expect(LivePi.ProjectsMock, :list_projects, 2, fn -> [project] end)

    expect(LivePi.ProjectsMock, :browse, 2, fn nil ->
      {:ok,
       %{current_path: "/srv/projects", root_path: "/srv/projects", parent_path: nil, entries: []}}
    end)

    expect(LivePi.ProjectsMock, :select_project, fn path ->
      assert path == project.path
      {:ok, project}
    end)

    expect(LivePi.PiMock, :start_session, fn opts ->
      assert opts[:project_path] == project.path
      assert is_binary(opts[:browser_session_id])
      {:ok, session_ref}
    end)

    expect(LivePi.PiMock, :get_messages, fn ^session_ref ->
      {:ok,
       [
         %{
           "role" => "assistant",
           "content" => [%{"type" => "text", "text" => "Ready."}],
           "timestamp" => 1
         }
       ]}
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#project-select-#{project.id}")
    |> render_click()

    assert has_element?(view, "#chat-form")
    assert render(view) =~ "apps/api"
    assert render(view) =~ "Ready."
  end

  test "clone_project submits clone form and selects cloned project", %{conn: conn} do
    project = %Project{project_fixture() | source: :cloned}
    session_ref = start_supervised!({Task, fn -> Process.sleep(:infinity) end})

    expect(LivePi.ProjectsMock, :list_projects, 2, fn -> [] end)

    expect(LivePi.ProjectsMock, :browse, 2, fn nil ->
      {:ok,
       %{current_path: "/srv/projects", root_path: "/srv/projects", parent_path: nil, entries: []}}
    end)

    expect(LivePi.ProjectsMock, :clone_project, fn "https://github.com/example/api.git",
                                                   [name: "api"] ->
      {:ok, project}
    end)

    expect(LivePi.PiMock, :start_session, fn _opts -> {:ok, session_ref} end)
    expect(LivePi.PiMock, :get_messages, fn ^session_ref -> {:ok, []} end)
    expect(LivePi.ProjectsMock, :list_projects, fn -> [project] end)

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#clone-form", clone: %{repo_url: "https://github.com/example/api.git", name: "api"})
    |> render_submit()

    assert render(view) =~ "Project cloned successfully."
    assert render(view) =~ "apps/api"
  end

  test "sending a prompt renders local user message and streaming assistant text", %{conn: conn} do
    project = project_fixture()
    session_ref = start_supervised!({Task, fn -> Process.sleep(:infinity) end})

    expect(LivePi.ProjectsMock, :list_projects, 2, fn -> [project] end)

    expect(LivePi.ProjectsMock, :browse, 2, fn nil ->
      {:ok,
       %{current_path: "/srv/projects", root_path: "/srv/projects", parent_path: nil, entries: []}}
    end)

    expect(LivePi.ProjectsMock, :select_project, fn path ->
      assert path == project.path
      {:ok, project}
    end)

    expect(LivePi.PiMock, :start_session, fn _opts -> {:ok, session_ref} end)
    expect(LivePi.PiMock, :get_messages, fn ^session_ref -> {:ok, []} end)
    expect(LivePi.PiMock, :prompt, fn ^session_ref, "Inspect the app", [] -> :ok end)

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#project-select-#{project.id}") |> render_click()

    view
    |> form("#chat-form", chat: %{message: "Inspect the app"})
    |> render_submit()

    assert render(view) =~ "Inspect the app"

    send(
      view.pid,
      {:pi_event, session_ref,
       %{
         "type" => "message_update",
         "assistantMessageEvent" => %{"type" => "text_delta", "delta" => "Working..."}
       }}
    )

    assert render(view) =~ "Working..."

    send(
      view.pid,
      {:pi_event, session_ref,
       %{
         "type" => "agent_end",
         "messages" => [
           %{"role" => "user", "content" => "Inspect the app", "timestamp" => 1},
           %{
             "role" => "assistant",
             "content" => [%{"type" => "text", "text" => "Done."}],
             "timestamp" => 2
           }
         ]
       }}
    )

    assert render(view) =~ "Done."
  end

  defp project_fixture do
    %Project{
      id: "project-1",
      name: "api",
      path: "/srv/projects/apps/api",
      root: "/srv/projects",
      source: :existing,
      clone_status: :ready
    }
  end
end
