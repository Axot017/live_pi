defmodule LivePiWeb.PageControllerTest do
  use LivePiWeb.ConnCase

  import Mox

  test "GET / renders the workspace shell", %{conn: conn} do
    expect(LivePi.ProjectsMock, :list_projects, fn -> [] end)

    expect(LivePi.ProjectsMock, :browse, fn nil ->
      {:ok,
       %{current_path: "/srv/projects", root_path: "/srv/projects", parent_path: nil, entries: []}}
    end)

    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Pi agent workspace"
  end
end
