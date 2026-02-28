defmodule RevixWeb.Controller.HelpersTest do
  use ExUnit.Case, async: true

  import RevixWeb.Controller.Helpers

  describe "to_place_activity/1" do
    test "returns a Place object with required fields" do
      place = %Revix.Places.Place{
        uri: "https://example.com/places/abc123",
        url: "https://example.com/places/abc123",
        name: "Test Cafe",
        coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326},
        content: nil
      }

      result = to_place_activity(place)

      assert result["type"] == "Place"
      assert result["id"] == place.uri
      assert result["name"] == "Test Cafe"
      assert result["url"] == place.url
    end

    test "includes longitude and latitude from coordinates" do
      place = %Revix.Places.Place{
        uri: "https://example.com/places/abc",
        url: "https://example.com/places/abc",
        name: "Mountain View",
        coordinates: %Geo.Point{coordinates: {-122.08, 37.42}, srid: 4326},
        content: nil
      }

      result = to_place_activity(place)

      assert result["longitude"] == -122.08
      assert result["latitude"] == 37.42
    end

    test "omits coordinates when nil" do
      place = %Revix.Places.Place{
        uri: "https://example.com/places/abc",
        url: "https://example.com/places/abc",
        name: "No Coords",
        coordinates: nil,
        content: nil
      }

      result = to_place_activity(place)

      refute Map.has_key?(result, "longitude")
      refute Map.has_key?(result, "latitude")
    end

    test "includes summary when content is present" do
      place = %Revix.Places.Place{
        uri: "https://example.com/places/abc",
        url: "https://example.com/places/abc",
        name: "Described Place",
        coordinates: nil,
        content: "A great little cafe."
      }

      result = to_place_activity(place)

      assert result["summary"] == "A great little cafe."
    end

    test "omits summary when content is nil" do
      place = %Revix.Places.Place{
        uri: "https://example.com/places/abc",
        url: "https://example.com/places/abc",
        name: "No Description",
        coordinates: nil,
        content: nil
      }

      result = to_place_activity(place)

      refute Map.has_key?(result, "summary")
    end
  end

  describe "to_person_activity/1" do
    @base_person %Revix.People.Person{
      id: "abc12345678",
      uri: "https://example.com/users/abc12345678",
      url: "https://example.com/users/abc12345678",
      username: "alice",
      display_name: "Alice Smith",
      public_key: nil
    }

    test "uses display_name for name when present" do
      result = to_person_activity(@base_person)
      assert result["name"] == "Alice Smith"
    end

    test "falls back to Someone for name when display_name is nil" do
      person = %{@base_person | display_name: nil}
      result = to_person_activity(person)
      assert result["name"] == "Someone"
    end

    test "uses username for preferredUsername when present" do
      result = to_person_activity(@base_person)
      assert result["preferredUsername"] == "alice"
    end

    test "falls back to id for preferredUsername when username is nil" do
      person = %{@base_person | username: nil}
      result = to_person_activity(person)
      assert result["preferredUsername"] == "abc12345678"
    end

    test "includes icon with Image type and png mediaType" do
      result = to_person_activity(@base_person)
      assert %{"type" => "Image", "mediaType" => "image/png", "url" => url} = result["icon"]
      assert String.starts_with?(url, "http")
    end

    test "icon url falls back to identicon when avatar is nil" do
      result = to_person_activity(@base_person)
      assert %{"url" => url} = result["icon"]
      assert String.contains?(url, @base_person.id)
      assert String.starts_with?(url, "http")
    end
  end

  describe "to_checkin_activity/1" do
    test "returns a Note object with required fields" do
      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc123",
        url: "https://example.com/checkins/abc123",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil
      }

      result = to_checkin_activity(checkin)

      assert result["type"] == "Note"
      assert result["id"] == checkin.uri
      assert result["url"] == checkin.url
      assert result["attributedTo"] == checkin.author_uri
      assert result["published"] == "2026-02-19T14:00:00Z"
      assert result["startTime"] == "2026-02-19T12:00:00Z"
    end

    test "always includes checkin hashtag in tag" do
      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc123",
        url: "https://example.com/checkins/abc123",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil
      }

      result = to_checkin_activity(checkin)

      assert result["tag"] == [%{"type" => "Hashtag", "name" => "#checkin"}]
    end

    test "includes content and mediaType when content_html is present" do
      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: "Great place",
        content_html: "<p>Great place</p>",
        place_uri: nil,
        place: nil,
        context: nil
      }

      result = to_checkin_activity(checkin)

      assert result["content"] == "<p>Great place</p>"
      assert result["mediaType"] == "text/html"
    end

    test "falls back to raw content when content_html is nil" do
      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: "Just text",
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil
      }

      result = to_checkin_activity(checkin)

      assert result["content"] == "Just text"
      assert result["mediaType"] == "text/html"
    end

    test "omits content fields when content is nil" do
      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil
      }

      result = to_checkin_activity(checkin)

      refute Map.has_key?(result, "content")
      refute Map.has_key?(result, "mediaType")
    end

    test "includes location as plain URI when place_uri is set but place is not loaded" do
      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: "https://example.com/places/pqr",
        place: nil,
        context: nil
      }

      result = to_checkin_activity(checkin)

      assert result["location"] == "https://example.com/places/pqr"
    end

    test "includes location as Place object when place is loaded" do
      place = %Revix.Places.Place{
        uri: "https://example.com/places/pqr",
        url: "https://example.com/places/pqr",
        name: "Test Cafe",
        coordinates: nil,
        content: nil
      }

      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: "https://example.com/places/pqr",
        place: place,
        context: nil
      }

      result = to_checkin_activity(checkin)

      assert result["location"] == %{
               "id" => "https://example.com/places/pqr",
               "type" => "Place",
               "name" => "Test Cafe"
             }
    end

    test "includes coordinates in location when place has coordinates" do
      place = %Revix.Places.Place{
        uri: "https://example.com/places/pqr",
        url: "https://example.com/places/pqr",
        name: "Mountain View",
        coordinates: %Geo.Point{coordinates: {-122.08, 37.42}, srid: 4326},
        content: nil
      }

      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: "https://example.com/places/pqr",
        place: place,
        context: nil
      }

      result = to_checkin_activity(checkin)
      location = result["location"]

      assert location["longitude"] == -122.08
      assert location["latitude"] == 37.42
    end

    test "omits location when place_uri is nil" do
      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil
      }

      result = to_checkin_activity(checkin)

      refute Map.has_key?(result, "location")
    end

    test "includes context when set" do
      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: "https://example.com/checkins/abc"
      }

      result = to_checkin_activity(checkin)

      assert result["context"] == "https://example.com/checkins/abc"
    end

    test "omits context when nil" do
      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil
      }

      result = to_checkin_activity(checkin)

      refute Map.has_key?(result, "context")
    end

    test "handles nil published_at_utc" do
      checkin = %Revix.Entries.Entry{
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        published_at_utc: nil,
        starts_at_utc: nil,
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil
      }

      result = to_checkin_activity(checkin)

      assert is_nil(result["published"])
      assert is_nil(result["startTime"])
    end
  end
end
