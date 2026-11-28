defmodule RevixWeb.SiteTitleDescriptionsTest do
  use RevixWeb.ConnCase, async: true

  import Revix.PeopleFixtures

  setup do
    {:ok, _} = Revix.Sites.update_site(RevixWeb.CanonicalRoutes.home_url(), %{title: "Trail Log"})
    :ok
  end

  defp descriptions(conn, path) do
    doc = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

    {doc |> LazyHTML.query("meta[name=description]") |> LazyHTML.attribute("content"),
     doc |> LazyHTML.query("meta[property='og:description']") |> LazyHTML.attribute("content")}
  end

  for {path, expected} <- [
        {"/checkins", "Recent check-ins on Trail Log."},
        {"/posts", "Posts from the Trail Log community."},
        {"/places", "Browse places on Trail Log."}
      ] do
    test "#{path} describes itself with the site title", %{conn: conn} do
      assert descriptions(conn, unquote(path)) == {[unquote(expected)], [unquote(expected)]}
    end
  end

  test "a person's page describes their activity on this site", %{conn: conn} do
    person = person_fixture()
    Revix.Repo.update!(Ecto.Changeset.change(person, display_name: "Ada"))

    {[description], _og} = descriptions(conn, "/people/#{person.id}")

    assert description == "Ada's activity on Trail Log."
  end
end
