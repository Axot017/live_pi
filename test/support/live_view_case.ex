defmodule LivePiWeb.LiveViewCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint LivePiWeb.Endpoint

      use LivePiWeb, :verified_routes

      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import LivePiWeb.LiveViewCase
    end
  end

  setup tags do
    Mox.set_mox_from_context(tags)
    Mox.verify_on_exit!()

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
