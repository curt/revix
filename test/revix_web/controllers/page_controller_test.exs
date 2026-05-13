defmodule RevixWeb.PageControllerTest do
  use RevixWeb.ConnCase

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.LikesFixtures

  defp create_comment(scope, checkin, attrs) do
    uri_fn = fn id -> "https://example.com/notes/#{id}" end
    Revix.Entries.create_comment(scope, checkin, attrs, uri_fn, uri_fn)
  end

  describe "GET / checkin activity" do
    test "renders the home page", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Home Page"
    end

    test "renders empty page when no activity exists", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200)
    end

    test "displays checkin with place name and verb", %{conn: conn} do
      place = place_fixture(%{name: "Disneyland"})
      checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ "Disneyland"
      assert response =~ "checked into"
    end

    test "displays checkin author display name", %{conn: conn} do
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Alice"})
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Alice"
    end

    test "displays checkin date and timezone abbreviation", %{conn: conn} do
      place = place_fixture()

      checkin_fixture(%{
        place_uri: place.uri,
        starts_at_utc: ~U[2026-02-16 18:37:00Z],
        starts_at_local: ~N[2026-02-16 10:37:00],
        starts_tz: "America/Los_Angeles"
      })

      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ "2026-02-16"
      assert response =~ "10:37 PST"
    end

    test "links to author profile from checkin", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ ~s(href="http://localhost:4000/people/#{person.id}")
    end

    test "links to the checkin URL", %{conn: conn} do
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, url: "http://example.com/123"})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "http://example.com/123"
    end

    test "shows 'somewhere' when checkin has no place", %{conn: conn} do
      checkin_fixture(%{place_uri: "https://example.com/places/nonexistent"})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "somewhere"
    end

    test "shows 'Someone' when checkin has no resolvable author", %{conn: conn} do
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, author_uri: "https://example.com/people/ghost"})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Someone"
    end
  end

  describe "GET / like activity" do
    setup do
      place = place_fixture(%{name: "The Coffee Shop"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      %{place: place, checkin: checkin}
    end

    test "displays like verb and heart icon", %{conn: conn, checkin: checkin} do
      like_fixture(%{object_uri: checkin.uri})

      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ "liked"
      assert response =~ "hero-heart-solid"
    end

    test "displays like author name", %{conn: conn, checkin: checkin} do
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Bob"})
      like_fixture(%{author_uri: person.uri, object_uri: checkin.uri})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Bob"
    end

    test "displays liked place name when object resolves to a checkin with a place", %{
      conn: conn,
      checkin: checkin,
      place: place
    } do
      like_fixture(%{object_uri: checkin.uri})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ place.name
    end

    test "shows 'a checkin' when liked object has no resolvable place", %{conn: conn} do
      like_fixture(%{object_uri: "https://example.com/entries/nonexistent"})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "a checkin"
    end

    test "shows 'Someone' when like has no resolvable author", %{conn: conn, checkin: checkin} do
      like_fixture(%{author_uri: "https://example.com/people/ghost", object_uri: checkin.uri})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Someone"
    end

    test "displays like date and timezone", %{conn: conn, checkin: checkin} do
      like_fixture(%{object_uri: checkin.uri, published_tz: "America/New_York"})

      conn = get(conn, ~p"/")
      # date is rendered, timezone abbreviation is EST or EDT
      response = html_response(conn, 200)
      assert response =~ ~r/\d{4}-\d{2}-\d{2}/
      assert response =~ ~r/E[SD]T/
    end

    test "hides remote likes from unauthenticated visitors", %{conn: conn, checkin: checkin} do
      {:ok, _like} =
        Revix.Likes.upsert_inbound_like(%{
          author_uri: "https://remote.example/users/alice",
          object_uri: checkin.uri,
          like_uri: "https://remote.example/likes/1"
        })

      conn = get(conn, ~p"/")
      refute html_response(conn, 200) =~ "hero-heart-solid"
    end

    test "shows remote likes to authenticated users", %{conn: conn, checkin: checkin} do
      person = person_fixture()

      {:ok, _like} =
        Revix.Likes.upsert_inbound_like(%{
          author_uri: "https://remote.example/users/alice",
          object_uri: checkin.uri,
          like_uri: "https://remote.example/likes/2"
        })

      conn = conn |> log_in_person(person) |> get(~p"/")
      assert html_response(conn, 200) =~ "hero-heart-solid"
    end
  end

  describe "GET / comment activity" do
    setup do
      scope = Revix.People.Scope.for_person(person_fixture())
      place = place_fixture(%{name: "The Diner"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      %{scope: scope, place: place, checkin: checkin}
    end

    test "displays comment verb", %{conn: conn, scope: scope, checkin: checkin} do
      create_comment(scope, checkin, %{
        "content" => "Nice spot!",
        "published_tz" => "UTC"
      })

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "commented on"
    end

    test "displays comment author name", %{conn: conn, checkin: checkin} do
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Carol"})
      scope = Revix.People.Scope.for_person(person)

      create_comment(scope, checkin, %{
        "content" => "Great!",
        "published_tz" => "UTC"
      })

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Carol"
    end

    test "links to the parent checkin place", %{
      conn: conn,
      scope: scope,
      checkin: checkin,
      place: place
    } do
      create_comment(scope, checkin, %{
        "content" => "Love it",
        "published_tz" => "UTC"
      })

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ place.name
    end

    test "shows 'a checkin' when comment has no resolvable parent place", %{
      conn: conn,
      scope: scope
    } do
      orphan_checkin = checkin_fixture(%{place_uri: "https://example.com/places/gone"})

      create_comment(scope, orphan_checkin, %{
        "content" => "Still here",
        "published_tz" => "UTC"
      })

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "a checkin"
    end

    test "displays comment date and timezone", %{conn: conn, scope: scope, checkin: checkin} do
      create_comment(scope, checkin, %{
        "content" => "Testing",
        "published_tz" => "America/Chicago"
      })

      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ ~r/\d{4}-\d{2}-\d{2}/
      assert response =~ ~r/C[SD]T/
    end
  end

  describe "GET / GeoJSON format" do
    test "returns GeoJSON for geo format", %{conn: conn} do
      place_fixture()

      conn = get(conn, "/?_format=geo")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"
    end

    test "includes all places, not just those with checkins", %{conn: conn} do
      place_fixture(%{name: "Place With Checkin"})
      place_fixture(%{name: "Place Without Checkin"})

      conn = get(conn, "/?_format=geo")
      response = json_response(conn, 200)
      names = Enum.map(response["features"], & &1["properties"]["name"])
      assert "Place With Checkin" in names
      assert "Place Without Checkin" in names
    end

    test "includes place names in feature properties", %{conn: conn} do
      place_fixture(%{name: "Test Place"})

      conn = get(conn, "/?_format=geo")
      response = json_response(conn, 200)
      feature = List.first(response["features"])
      assert feature["properties"]["name"] == "Test Place"
    end
  end
end
