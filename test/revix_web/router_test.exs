defmodule RevixWeb.RouterTest do
  use ExUnit.Case, async: true

  # These endpoints had no caller and diverged from the LiveViews that do the
  # same work (the note DELETE hard-deleted instead of tombstoning). Keep them
  # from coming back unnoticed.
  @removed [
    {"POST", "/notes"},
    {"PUT", "/notes/abc"},
    {"DELETE", "/notes/abc"},
    {"POST", "/api/likes"},
    {"DELETE", "/api/likes"},
    {"POST", "/api/entry_people"},
    {"DELETE", "/api/entry_people"},
    {"GET", "/api/people/search"},
    {"GET", "/api/places/search"}
  ]

  for {method, path} <- @removed do
    test "#{method} #{path} is not routed" do
      assert Phoenix.Router.route_info(
               RevixWeb.Router,
               unquote(method),
               unquote(path),
               "localhost"
             ) ==
               :error
    end
  end

  test "GET /notes/:id is still routed" do
    assert %{plug: RevixWeb.NoteController, plug_opts: :show} =
             Phoenix.Router.route_info(RevixWeb.Router, "GET", "/notes/abc", "localhost")
  end

  # A hook declared on the live_session already runs for every LiveView in it;
  # declaring it again on the module runs it twice per mount (two token
  # lookups, two site lookups) on both the dead render and the connected mount.
  test "no routed LiveView repeats an on_mount hook from its live_session" do
    repeated =
      for %{metadata: %{phoenix_live_view: {module, _action, _opts, live_session}}} <-
            Phoenix.Router.routes(RevixWeb.Router),
          session_ids = hook_ids(live_session.extra[:on_mount]),
          id <- hook_ids(module.__live__()[:lifecycle].mount),
          id in session_ids,
          uniq: true,
          do: {module, id}

    assert repeated == []
  end

  defp hook_ids(nil), do: []
  defp hook_ids(hooks), do: Enum.map(hooks, & &1.id)
end
