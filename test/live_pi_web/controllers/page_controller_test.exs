defmodule LivePiWeb.PageControllerTest do
  use LivePiWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "repository url"
    assert html =~ "loading projects from"
    assert html =~ "No project selected"
  end
end
