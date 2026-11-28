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

  @owner_live_pages [
    "/pings",
    "/places/new",
    "/places/abc/edit",
    "/places/abc/merge",
    "/posts/new",
    "/settings/site"
  ]

  for path <- @owner_live_pages do
    test "#{path} requires an owner on both the page load and the live connection" do
      info = Phoenix.Router.route_info(RevixWeb.Router, "GET", unquote(path), "localhost")
      {_module, _action, _opts, live_session} = info.phoenix_live_view

      assert :require_owner in info.pipe_through
      assert {RevixWeb.Live.PersonAuth, :require_owner} in hook_ids(live_session.extra[:on_mount])
    end
  end

  for path <- ["/checkins/abc/retransform_images", "/posts/abc/retransform_images"] do
    test "POST #{path} requires an owner" do
      info = Phoenix.Router.route_info(RevixWeb.Router, "POST", unquote(path), "localhost")
      assert :require_owner in info.pipe_through
    end
  end

  # Any signed-in person can check in from a place: the fallback when the
  # check-in page can't get a location.
  test "/places/:id/checkins/new is not behind the owner gate" do
    info =
      Phoenix.Router.route_info(RevixWeb.Router, "GET", "/places/abc/checkins/new", "localhost")

    refute :require_owner in info.pipe_through
  end
end
