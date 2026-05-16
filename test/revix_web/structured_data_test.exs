defmodule RevixWeb.StructuredDataTest do
  use ExUnit.Case, async: true

  alias Revix.Entries.Entry
  alias Revix.EntryPlaces.EntryPlace
  alias Revix.People.Person
  alias Revix.Places.Place
  alias RevixWeb.StructuredData

  # ── place_json_ld/1 ───────────────────────────────────────────────────────────

  describe "place_json_ld/1" do
    test "returns TouristAttraction with correct context, type, name, and url" do
      place = place(%{name: "Test Cafe", id: "aaaaaaaaaaa", slug: "test-cafe"})
      result = StructuredData.place_json_ld(place)

      assert result["@context"] == "https://schema.org"
      assert result["@type"] == "TouristAttraction"
      assert result["name"] == "Test Cafe"
      assert result["url"] =~ "/places/aaaaaaaaaaa/test-cafe"
    end

    test "includes GeoCoordinates when place has coordinates" do
      place =
        place(%{
          name: "Geo Cafe",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      result = StructuredData.place_json_ld(place)

      assert result["geo"]["@type"] == "GeoCoordinates"
      assert result["geo"]["latitude"] == 40.0
      assert result["geo"]["longitude"] == -105.0
    end

    test "longitude and latitude are not swapped" do
      place =
        place(%{
          coordinates: %Geo.Point{coordinates: {-105.123, 40.456}, srid: 4326}
        })

      result = StructuredData.place_json_ld(place)

      assert result["geo"]["latitude"] == 40.456
      assert result["geo"]["longitude"] == -105.123
    end

    test "omits geo when place has no coordinates" do
      place = place(%{coordinates: nil})
      result = StructuredData.place_json_ld(place)

      refute Map.has_key?(result, "geo")
    end

    test "includes sameAs OSM URL when place has osm_type and osm_id" do
      place = place(%{osm_type: :node, osm_id: 12345})
      result = StructuredData.place_json_ld(place)

      assert result["sameAs"] == "https://www.openstreetmap.org/node/12345"
    end

    test "omits sameAs when place has no OSM data" do
      place = place(%{osm_type: nil, osm_id: nil})
      result = StructuredData.place_json_ld(place)

      refute Map.has_key?(result, "sameAs")
    end
  end

  # ── checkin_json_ld/1 ─────────────────────────────────────────────────────────

  describe "checkin_json_ld/1" do
    test "returns Event with correct context, type, startDate, and url" do
      p = place(%{name: "The Spot", slug: "the-spot"})

      checkin =
        checkin(%{
          id: "bbbbbbbbbbb",
          place: p,
          starts_at_utc: ~U[2026-02-14 15:00:00Z]
        })

      result = StructuredData.checkin_json_ld(checkin)

      assert result["@context"] == "https://schema.org"
      assert result["@type"] == "Event"
      assert result["startDate"] == "2026-02-14T15:00:00Z"
      assert result["url"] =~ "/checkins/bbbbbbbbbbb/the-spot"
    end

    test "name is 'Checkin at Place Name' when place is loaded" do
      checkin = checkin(%{place: place(%{name: "Mountain View"})})
      result = StructuredData.checkin_json_ld(checkin)
      assert result["name"] == "Checkin at Mountain View"
    end

    test "name is 'Checkin' when place is nil" do
      checkin = checkin(%{place: nil})
      result = StructuredData.checkin_json_ld(checkin)
      assert result["name"] == "Checkin"
    end

    test "includes location with name and geo when place has coordinates" do
      p =
        place(%{
          name: "The Spot",
          coordinates: %Geo.Point{coordinates: {-104.0, 39.0}, srid: 4326}
        })

      checkin = checkin(%{place: p})
      result = StructuredData.checkin_json_ld(checkin)

      assert result["location"]["@type"] == "Place"
      assert result["location"]["name"] == "The Spot"
      assert result["location"]["geo"]["latitude"] == 39.0
      assert result["location"]["geo"]["longitude"] == -104.0
    end

    test "includes location without geo when place has no coordinates" do
      p = place(%{name: "The Spot", coordinates: nil})
      checkin = checkin(%{place: p})
      result = StructuredData.checkin_json_ld(checkin)

      assert result["location"]["name"] == "The Spot"
      refute Map.has_key?(result["location"], "geo")
    end

    test "includes sameAs in location when place has OSM data" do
      p = place(%{name: "The Spot", osm_type: :relation, osm_id: 77777})
      checkin = checkin(%{place: p})
      result = StructuredData.checkin_json_ld(checkin)

      assert result["location"]["sameAs"] == "https://www.openstreetmap.org/relation/77777"
    end

    test "omits sameAs from location when place has no OSM data" do
      p = place(%{name: "The Spot", osm_type: nil, osm_id: nil})
      checkin = checkin(%{place: p})
      result = StructuredData.checkin_json_ld(checkin)

      refute Map.has_key?(result["location"], "sameAs")
    end

    test "omits location when place is nil" do
      checkin = checkin(%{place: nil})
      result = StructuredData.checkin_json_ld(checkin)
      refute Map.has_key?(result, "location")
    end

    test "includes organizer with display_name and url when author is loaded" do
      author =
        person(%{
          display_name: "Alice Example",
          username: "alice",
          url: "http://example.com/@alice"
        })

      checkin = checkin(%{author: author})
      result = StructuredData.checkin_json_ld(checkin)

      assert result["organizer"]["@type"] == "Person"
      assert result["organizer"]["name"] == "Alice Example"
      assert result["organizer"]["url"] == "http://example.com/@alice"
    end

    test "falls back to username when display_name is nil" do
      author = person(%{display_name: nil, username: "alice"})
      checkin = checkin(%{author: author})
      result = StructuredData.checkin_json_ld(checkin)

      assert result["organizer"]["name"] == "alice"
    end

    test "falls back to username when display_name is empty string" do
      author = person(%{display_name: "", username: "alice"})
      checkin = checkin(%{author: author})
      result = StructuredData.checkin_json_ld(checkin)

      assert result["organizer"]["name"] == "alice"
    end

    test "omits url from organizer when author url is nil" do
      author = person(%{display_name: "Alice Example", url: nil})
      checkin = checkin(%{author: author})
      result = StructuredData.checkin_json_ld(checkin)

      refute Map.has_key?(result["organizer"], "url")
    end

    test "omits organizer when author is nil" do
      checkin = checkin(%{author: nil})
      result = StructuredData.checkin_json_ld(checkin)
      refute Map.has_key?(result, "organizer")
    end
  end

  # ── post_json_ld/1 ────────────────────────────────────────────────────────────

  describe "post_json_ld/1" do
    test "returns BlogPosting with correct context, type, datePublished, and url" do
      p =
        post(%{
          id: "ccccccccccc",
          published_at_utc: ~U[2026-05-10 14:00:00Z],
          published_at_local: ~N[2026-05-10 10:00:00],
          name: "My Post"
        })

      result = StructuredData.post_json_ld(p)

      assert result["@context"] == "https://schema.org"
      assert result["@type"] == "BlogPosting"
      assert result["datePublished"] == "2026-05-10T14:00:00Z"
      assert result["url"] =~ "/posts/ccccccccccc"
    end

    test "includes headline when name is present" do
      p = post(%{name: "My Great Post"})
      result = StructuredData.post_json_ld(p)
      assert result["headline"] == "My Great Post"
    end

    test "omits headline when name is nil" do
      p = post(%{name: nil})
      result = StructuredData.post_json_ld(p)
      refute Map.has_key?(result, "headline")
    end

    test "omits headline when name is empty string" do
      p = post(%{name: ""})
      result = StructuredData.post_json_ld(p)
      refute Map.has_key?(result, "headline")
    end

    test "includes author with display_name and url when author is loaded" do
      author =
        person(%{display_name: "Bob Writer", username: "bob", url: "http://example.com/@bob"})

      p = post(%{author: author})
      result = StructuredData.post_json_ld(p)

      assert result["author"]["@type"] == "Person"
      assert result["author"]["name"] == "Bob Writer"
      assert result["author"]["url"] == "http://example.com/@bob"
    end

    test "falls back to username when display_name is nil" do
      author = person(%{display_name: nil, username: "bob"})
      p = post(%{author: author})
      result = StructuredData.post_json_ld(p)

      assert result["author"]["name"] == "bob"
    end

    test "omits url from author when author url is nil" do
      author = person(%{display_name: "Bob Writer", url: nil})
      p = post(%{author: author})
      result = StructuredData.post_json_ld(p)

      refute Map.has_key?(result["author"], "url")
    end

    test "omits author when author is nil" do
      p = post(%{author: nil})
      result = StructuredData.post_json_ld(p)
      refute Map.has_key?(result, "author")
    end

    test "includes description when summary is present" do
      p = post(%{summary: "A short summary."})
      result = StructuredData.post_json_ld(p)
      assert result["description"] == "A short summary."
    end

    test "omits description when summary is nil" do
      p = post(%{summary: nil})
      result = StructuredData.post_json_ld(p)
      refute Map.has_key?(result, "description")
    end

    test "omits contentLocation when post has no places" do
      p = post(%{entry_places: []})
      result = StructuredData.post_json_ld(p)
      refute Map.has_key?(result, "contentLocation")
    end

    test "includes contentLocation list when post has one place" do
      ep = entry_place(place(%{name: "The Library"}))
      p = post(%{entry_places: [ep]})
      result = StructuredData.post_json_ld(p)

      assert [location] = result["contentLocation"]
      assert location["@type"] == "Place"
      assert location["name"] == "The Library"
    end

    test "includes contentLocation list when post has multiple places" do
      ep1 = entry_place(place(%{name: "First Stop"}))
      ep2 = entry_place(place(%{name: "Second Stop"}))
      p = post(%{entry_places: [ep1, ep2]})
      result = StructuredData.post_json_ld(p)

      assert length(result["contentLocation"]) == 2
      names = Enum.map(result["contentLocation"], & &1["name"])
      assert "First Stop" in names
      assert "Second Stop" in names
    end

    test "contentLocation includes geo and sameAs from place" do
      pl =
        place(%{
          name: "Geo Spot",
          coordinates: %Geo.Point{coordinates: {-104.0, 39.0}, srid: 4326},
          osm_type: :way,
          osm_id: 99999
        })

      p = post(%{entry_places: [entry_place(pl)]})
      result = StructuredData.post_json_ld(p)

      [location] = result["contentLocation"]
      assert location["geo"]["latitude"] == 39.0
      assert location["sameAs"] == "https://www.openstreetmap.org/way/99999"
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp place(attrs) do
    defaults = %{
      id: "aaaaaaaaaaa",
      name: "A Place",
      slug: "a-place",
      uri: "http://example.com/places/aaaaaaaaaaa",
      url: "http://example.com/places/aaaaaaaaaaa",
      coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326},
      osm_type: nil,
      osm_id: nil,
      content: nil,
      content_html: nil
    }

    struct(Place, Map.merge(defaults, attrs))
  end

  defp person(attrs) do
    defaults = %{
      id: "ppppppppppp",
      display_name: "A Person",
      username: "aperson",
      uri: "http://example.com/people/ppppppppppp",
      url: "http://example.com/@aperson"
    }

    struct(Person, Map.merge(defaults, attrs))
  end

  defp checkin(attrs) do
    p = Map.get(attrs, :place, place(%{}))

    defaults = %{
      id: "ccccccccccc",
      type: :checkin,
      uri: "http://example.com/checkins/ccccccccccc",
      url: "http://example.com/checkins/ccccccccccc",
      author_uri: "http://example.com/people/ppppppppppp",
      place_uri: p && p.uri,
      place: p,
      author: person(%{}),
      starts_at_utc: ~U[2026-01-01 12:00:00Z],
      name: nil,
      content: nil,
      summary: nil
    }

    struct(Entry, Map.merge(defaults, attrs))
  end

  defp post(attrs) do
    defaults = %{
      id: "ppppppppppp",
      type: :post,
      uri: "http://example.com/posts/ppppppppppp",
      url: "http://example.com/posts/ppppppppppp",
      author_uri: "http://example.com/people/qqqqqqqqqqq",
      author: person(%{}),
      published_at_utc: ~U[2026-05-10 14:00:00Z],
      published_at_local: ~N[2026-05-10 10:00:00],
      name: "My Post",
      content: nil,
      summary: nil,
      entry_places: []
    }

    struct(Entry, Map.merge(defaults, attrs))
  end

  defp entry_place(%Place{} = place) do
    struct(EntryPlace, %{
      entry_uri: "http://example.com/posts/ppppppppppp",
      place_uri: place.uri,
      place: place
    })
  end
end
