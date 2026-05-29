defmodule Revix.ActivityPubTest do
  use ExUnit.Case, async: true

  import Revix.ActivityPub

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
        id: "abc12345678",
        uri: "https://example.com/checkins/abc123",
        url: "https://example.com/checkins/abc123",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)

      assert result["type"] == "Note"
      assert result["id"] == checkin.uri
      assert result["url"] == checkin.url
      assert result["attributedTo"] == checkin.author_uri
      assert result["published"] == "2026-02-19T14:00:00Z"
      assert result["startTime"] == "2026-02-19T12:00:00Z"
      assert result["to"] == ["https://www.w3.org/ns/activitystreams#Public"]
      assert hd(result["cc"]) =~ "/people/authorid/followers"
      assert result["likes"] =~ "/entries/abc12345678/likes"
      assert result["replies"] =~ "/entries/abc12345678/replies"
    end

    test "always includes checkin hashtag in tag" do
      checkin = %Revix.Entries.Entry{
        id: "checkinid123",
        uri: "https://example.com/checkins/abc123",
        url: "https://example.com/checkins/abc123",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)

      assert result["tag"] == [%{"type" => "Hashtag", "name" => "#checkin"}]
    end

    test "includes content and mediaType when content_html is present" do
      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: "Great place",
        content_html: "<p>Great place</p>",
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)

      assert result["content"] == "<p>Great place</p>"
      assert result["mediaType"] == "text/html"
    end

    test "falls back to raw content when content_html is nil" do
      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: "Just text",
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)

      assert result["content"] == "Just text"
      assert result["mediaType"] == "text/html"
    end

    test "always includes content and mediaType even when content is nil" do
      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: nil,
        starts_at_local: nil,
        starts_tz: nil,
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        name: nil,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)

      assert is_binary(result["content"])
      assert result["content"] != ""
      assert result["mediaType"] == "text/html"
    end

    test "includes location as plain URI when place_uri is set but place is not loaded" do
      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: "https://example.com/places/pqr",
        place: nil,
        context: nil,
        entry_images: []
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
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: "https://example.com/places/pqr",
        place: place,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)

      assert result["location"] == %{
               "id" => "https://example.com/places/pqr",
               "type" => "Place",
               "name" => "Test Cafe",
               "url" => "https://example.com/places/pqr"
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
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: "https://example.com/places/pqr",
        place: place,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)
      location = result["location"]

      assert location["longitude"] == -122.08
      assert location["latitude"] == 37.42
      assert location["url"] == "https://example.com/places/pqr"
    end

    test "omits location when place_uri is nil" do
      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)

      refute Map.has_key?(result, "location")
    end

    test "includes context when set" do
      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: "https://example.com/checkins/abc",
        entry_images: []
      }

      result = to_checkin_activity(checkin)

      assert result["context"] == "https://example.com/checkins/abc"
    end

    test "omits context when nil" do
      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)

      refute Map.has_key?(result, "context")
    end

    test "handles nil published_at_utc" do
      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: nil,
        starts_at_utc: nil,
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)

      assert is_nil(result["published"])
      assert is_nil(result["startTime"])
    end

    test "omits attachment key when entry_images is empty" do
      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)

      refute Map.has_key?(result, "attachment")
    end

    test "includes attachment array when entry_images are present" do
      image = %Revix.Media.Image{
        id: 1,
        file: nil,
        content_type: "image/jpeg",
        caption: nil,
        caption_html: nil
      }

      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: [%Revix.Media.EntryImage{position: 0, image: image}]
      }

      result = to_checkin_activity(checkin)

      assert [attachment] = result["attachment"]
      assert attachment["type"] == "Document"
      assert attachment["mediaType"] == "image/jpeg"
      refute Map.has_key?(attachment, "name")
    end

    test "includes markdown-derived name and summary in attachment when caption is set" do
      image = %Revix.Media.Image{
        id: 1,
        file: nil,
        content_type: "image/jpeg",
        caption: "**A lovely** view",
        caption_html: "<p>ignored</p>"
      }

      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: [%Revix.Media.EntryImage{position: 0, image: image}]
      }

      result = to_checkin_activity(checkin)

      assert [attachment] = result["attachment"]
      assert attachment["name"] == "A lovely view"
      assert attachment["summary"] == "A lovely view"
    end

    test "truncates attachment name from caption markdown to 160 chars" do
      repeated = String.duplicate("mountain sunrise panorama ", 15)

      image = %Revix.Media.Image{
        id: 1,
        file: nil,
        content_type: "image/jpeg",
        caption: repeated,
        caption_html: "<p>ignored</p>"
      }

      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: [%Revix.Media.EntryImage{position: 0, image: image}]
      }

      result = to_checkin_activity(checkin)
      [attachment] = result["attachment"]
      name = attachment["name"]

      assert String.length(name) <= 160
      assert String.ends_with?(name, " ...")
    end

    test "truncates attachment summary from caption markdown to 1024 chars" do
      repeated = String.duplicate("mountain sunrise panorama ", 60)

      image = %Revix.Media.Image{
        id: 1,
        file: nil,
        content_type: "image/jpeg",
        caption: repeated,
        caption_html: "<p>ignored</p>"
      }

      checkin = %Revix.Entries.Entry{
        id: "checkinidabc",
        uri: "https://example.com/checkins/abc",
        url: "https://example.com/checkins/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: [%Revix.Media.EntryImage{position: 0, image: image}]
      }

      result = to_checkin_activity(checkin)
      [attachment] = result["attachment"]
      summary = attachment["summary"]

      assert String.length(summary) <= 1024
      assert String.ends_with?(summary, " ...")
    end

    test "omits updated when modified_at_utc is nil" do
      checkin = %Revix.Entries.Entry{
        id: "abc12345678",
        uri: "https://example.com/checkins/abc123",
        url: "https://example.com/checkins/abc123",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        modified_at_utc: nil,
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)
      refute Map.has_key?(result, "updated")
    end

    test "includes updated when modified_at_utc is later than published_at_utc" do
      checkin = %Revix.Entries.Entry{
        id: "abc12345678",
        uri: "https://example.com/checkins/abc123",
        url: "https://example.com/checkins/abc123",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-02-19 14:00:00Z],
        starts_at_utc: ~U[2026-02-19 12:00:00Z],
        modified_at_utc: ~U[2026-02-20 09:00:00Z],
        content: nil,
        content_html: nil,
        place_uri: nil,
        place: nil,
        context: nil,
        entry_images: []
      }

      result = to_checkin_activity(checkin)
      assert result["updated"] == "2026-02-20T09:00:00Z"
    end
  end

  describe "to_post_activity/1" do
    test "returns a Note object with required fields" do
      post = %Revix.Entries.Entry{
        id: "postidabc123",
        uri: "https://example.com/posts/abc123",
        url: "https://example.com/posts/abc123",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        name: nil,
        content: nil,
        content_html: nil,
        context: nil,
        entry_images: [],
        entry_places: []
      }

      result = to_post_activity(post)

      assert result["type"] == "Note"
      assert result["id"] == post.uri
      assert result["url"] == post.url
      assert result["attributedTo"] == post.author_uri
      assert result["published"] == "2026-05-10T14:00:00Z"
      assert result["to"] == ["https://www.w3.org/ns/activitystreams#Public"]
      assert hd(result["cc"]) =~ "/people/authorid/followers"
      refute Map.has_key?(result, "tag")
      refute Map.has_key?(result, "startTime")
    end

    test "includes name when set" do
      post = %Revix.Entries.Entry{
        id: "postidabcabc",
        uri: "https://example.com/posts/abc",
        url: "https://example.com/posts/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        name: "Hello World",
        content: nil,
        content_html: nil,
        context: nil,
        entry_images: [],
        entry_places: []
      }

      result = to_post_activity(post)

      assert result["name"] == "Hello World"
    end

    test "omits name when nil" do
      post = %Revix.Entries.Entry{
        id: "postidabcabc",
        uri: "https://example.com/posts/abc",
        url: "https://example.com/posts/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        name: nil,
        content: nil,
        content_html: nil,
        context: nil,
        entry_images: [],
        entry_places: []
      }

      result = to_post_activity(post)

      refute Map.has_key?(result, "name")
    end

    test "includes content and mediaType when content_html is present" do
      post = %Revix.Entries.Entry{
        id: "postidabcabc",
        uri: "https://example.com/posts/abc",
        url: "https://example.com/posts/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        name: nil,
        content: "Hello",
        content_html: "<p>Hello</p>",
        context: nil,
        entry_images: [],
        entry_places: []
      }

      result = to_post_activity(post)

      assert result["content"] == "<p>Hello</p>"
      assert result["mediaType"] == "text/html"
    end

    test "omits attachment key when entry_images is empty" do
      post = %Revix.Entries.Entry{
        id: "postidabcabc",
        uri: "https://example.com/posts/abc",
        url: "https://example.com/posts/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        name: nil,
        content: nil,
        content_html: nil,
        context: nil,
        entry_images: [],
        entry_places: []
      }

      result = to_post_activity(post)

      refute Map.has_key?(result, "attachment")
    end

    test "includes attachment array when entry_images are present" do
      image = %Revix.Media.Image{
        id: 1,
        file: "image.jpg",
        content_type: "image/png",
        caption: nil,
        caption_html: nil
      }

      post = %Revix.Entries.Entry{
        id: "postidabcabc",
        uri: "https://example.com/posts/abc",
        url: "https://example.com/posts/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        name: nil,
        content: nil,
        content_html: nil,
        context: nil,
        entry_images: [%Revix.Media.EntryImage{position: 0, image: image}],
        entry_places: []
      }

      result = to_post_activity(post)

      assert [attachment] = result["attachment"]
      assert attachment["type"] == "Document"
      assert attachment["mediaType"] == "image/png"
    end

    test "keeps protocol-relative attachment URLs as-is" do
      previous_asset_host = Application.get_env(:waffle, :asset_host)
      Application.put_env(:waffle, :asset_host, "//cdn.example.test")

      on_exit(fn ->
        if is_nil(previous_asset_host) do
          Application.delete_env(:waffle, :asset_host)
        else
          Application.put_env(:waffle, :asset_host, previous_asset_host)
        end
      end)

      image = %Revix.Media.Image{
        id: 1,
        file: "image.jpg",
        content_type: "image/png",
        caption: nil,
        caption_html: nil
      }

      post = %Revix.Entries.Entry{
        id: "postidabcabc",
        uri: "https://example.com/posts/abc",
        url: "https://example.com/posts/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        name: nil,
        content: nil,
        content_html: nil,
        context: nil,
        entry_images: [%Revix.Media.EntryImage{position: 0, image: image}],
        entry_places: []
      }

      result = to_post_activity(post)
      [attachment] = result["attachment"]

      assert String.starts_with?(attachment["url"], "//")
    end

    test "omits location and attachment when entry places/images are non-lists" do
      post = %Revix.Entries.Entry{
        id: "postidabcabc",
        uri: "https://example.com/posts/abc",
        url: "https://example.com/posts/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        name: nil,
        content: nil,
        content_html: nil,
        context: nil,
        entry_images: nil,
        entry_places: nil
      }

      result = to_post_activity(post)

      refute Map.has_key?(result, "attachment")
      refute Map.has_key?(result, "location")
    end

    test "includes location list with url when entry_places has a loaded place" do
      place = %Revix.Places.Place{
        uri: "https://example.com/places/pqr",
        url: "https://example.com/places/pqr",
        name: "Test Cafe",
        coordinates: nil,
        osm_type: nil,
        osm_id: nil
      }

      post = %Revix.Entries.Entry{
        id: "postidabcabc",
        uri: "https://example.com/posts/abc",
        url: "https://example.com/posts/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        name: nil,
        content: nil,
        content_html: nil,
        context: nil,
        entry_images: [],
        entry_places: [
          %Revix.EntryPlaces.EntryPlace{place_uri: "https://example.com/places/pqr", place: place}
        ]
      }

      result = to_post_activity(post)

      assert [location] = result["location"]
      assert location["id"] == "https://example.com/places/pqr"
      assert location["type"] == "Place"
      assert location["name"] == "Test Cafe"
      assert location["url"] == "https://example.com/places/pqr"
    end

    test "includes location with only id and type when place is not loaded" do
      post = %Revix.Entries.Entry{
        id: "postidabcabc",
        uri: "https://example.com/posts/abc",
        url: "https://example.com/posts/abc",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        name: nil,
        content: nil,
        content_html: nil,
        context: nil,
        entry_images: [],
        entry_places: [
          %Revix.EntryPlaces.EntryPlace{place_uri: "https://example.com/places/pqr", place: nil}
        ]
      }

      result = to_post_activity(post)

      assert [location] = result["location"]
      assert location == %{"id" => "https://example.com/places/pqr", "type" => "Place"}
    end

    test "omits updated when modified_at_utc is nil" do
      post = %Revix.Entries.Entry{
        id: "postidabc123",
        uri: "https://example.com/posts/abc123",
        url: "https://example.com/posts/abc123",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        modified_at_utc: nil,
        name: nil,
        content: nil,
        content_html: nil,
        context: nil,
        entry_images: [],
        entry_places: []
      }

      result = to_post_activity(post)
      refute Map.has_key?(result, "updated")
    end

    test "includes updated when modified_at_utc is later than published_at_utc" do
      post = %Revix.Entries.Entry{
        id: "postidabc123",
        uri: "https://example.com/posts/abc123",
        url: "https://example.com/posts/abc123",
        author_uri: "https://example.com/users/xyz",
        author: %Revix.People.Person{id: "authorid"},
        published_at_utc: ~U[2026-05-10 14:00:00Z],
        modified_at_utc: ~U[2026-05-11 08:00:00Z],
        name: nil,
        content: nil,
        content_html: nil,
        context: nil,
        entry_images: [],
        entry_places: []
      }

      result = to_post_activity(post)
      assert result["updated"] == "2026-05-11T08:00:00Z"
    end
  end

  describe "to_note_activity/1" do
    @base_note %Revix.Entries.Entry{
      id: "noteid12345",
      uri: "https://example.com/notes/noteid12345",
      url: "https://example.com/notes/noteid12345",
      author_uri: "https://example.com/users/xyz",
      author: %Revix.People.Person{id: "authorid"},
      published_at_utc: ~U[2026-05-17 10:00:00Z],
      content: nil,
      content_html: nil,
      in_reply_to_uri: nil,
      context: nil,
      entry_images: []
    }

    test "returns a Note object with required fields including likes and replies" do
      result = to_note_activity(@base_note)

      assert result["type"] == "Note"
      assert result["id"] == @base_note.uri
      assert result["url"] == @base_note.url
      assert result["attributedTo"] == @base_note.author_uri
      assert result["published"] == "2026-05-17T10:00:00Z"
      assert result["to"] == ["https://www.w3.org/ns/activitystreams#Public"]
      assert hd(result["cc"]) =~ "/people/authorid/followers"
      assert result["likes"] =~ "/entries/noteid12345/likes"
      assert result["replies"] =~ "/entries/noteid12345/replies"
    end

    test "omits inReplyTo when in_reply_to_uri is nil" do
      result = to_note_activity(@base_note)
      refute Map.has_key?(result, "inReplyTo")
    end

    test "includes inReplyTo when in_reply_to_uri is set" do
      note = %{@base_note | in_reply_to_uri: "https://example.com/checkins/parent"}
      result = to_note_activity(note)
      assert result["inReplyTo"] == "https://example.com/checkins/parent"
    end

    test "omits updated when modified_at_utc is nil" do
      result = to_note_activity(@base_note)
      refute Map.has_key?(result, "updated")
    end

    test "includes updated when modified_at_utc is later than published_at_utc" do
      note = %{@base_note | modified_at_utc: ~U[2026-05-18 09:00:00Z]}
      result = to_note_activity(note)
      assert result["updated"] == "2026-05-18T09:00:00Z"
    end

    test "omits updated when modified_at_utc equals published_at_utc" do
      note = %{@base_note | modified_at_utc: ~U[2026-05-17 10:00:00Z]}
      result = to_note_activity(note)
      refute Map.has_key?(result, "updated")
    end
  end
end
