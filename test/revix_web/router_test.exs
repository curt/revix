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
end
