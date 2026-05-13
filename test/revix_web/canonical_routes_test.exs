defmodule RevixWeb.CanonicalRoutesTest do
  use RevixWeb.ConnCase, async: true

  alias RevixWeb.CanonicalRoutes

  # ── People ───────────────────────────────────────────────────────────────────

  describe "person_path/1" do
    test "returns /@username when username is present" do
      assert CanonicalRoutes.person_path(%{id: "abc123", username: "alice"}) == "/@alice"
    end

    test "returns /people/:id when username is nil" do
      assert CanonicalRoutes.person_path(%{id: "abc123", username: nil}) == "/people/abc123"
    end

    test "returns /people/:id when username is empty string" do
      assert CanonicalRoutes.person_path("abc123", "") == "/people/abc123"
    end

    test "returns /people/:id from bare id" do
      assert CanonicalRoutes.person_path("abc123") == "/people/abc123"
    end
  end

  # ── Places ───────────────────────────────────────────────────────────────────

  describe "place_path/1" do
    test "returns /places/:id/:slug when slug is present" do
      assert CanonicalRoutes.place_path(%{id: "abc123", slug: "cafe-mox"}) ==
               "/places/abc123/cafe-mox"
    end

    test "returns /places/:id when slug is nil" do
      assert CanonicalRoutes.place_path(%{id: "abc123", slug: nil}) == "/places/abc123"
    end

    test "returns /places/:id when slug is empty string" do
      assert CanonicalRoutes.place_path("abc123", "") == "/places/abc123"
    end

    test "returns /places/:id from struct with no slug key" do
      assert CanonicalRoutes.place_path(%{id: "abc123"}) == "/places/abc123"
    end
  end

  # ── Checkins ─────────────────────────────────────────────────────────────────

  describe "checkin_path/1" do
    test "returns /checkins/:id/:slug when place slug is present" do
      assert CanonicalRoutes.checkin_path(%{id: "abc123", place: %{slug: "the-place"}}) ==
               "/checkins/abc123/the-place"
    end

    test "returns /checkins/:id when struct has no place" do
      assert CanonicalRoutes.checkin_path(%{id: "abc123"}) == "/checkins/abc123"
    end

    test "returns /checkins/:id from bare id" do
      assert CanonicalRoutes.checkin_path("abc123") == "/checkins/abc123"
    end

    test "returns /checkins/:id when slug is empty string" do
      assert CanonicalRoutes.checkin_path("abc123", "") == "/checkins/abc123"
    end
  end

  # ── Posts ────────────────────────────────────────────────────────────────────

  describe "post_path/1" do
    test "returns full dated path when published_at_local is set and name present" do
      local = ~N[2025-06-15 10:00:00]

      path =
        CanonicalRoutes.post_path(%{id: "abc123", published_at_local: local, name: "Hello World"})

      assert path =~ "/posts/abc123/2025/06/15/hello-world"
    end

    test "uses id as slug when name is nil" do
      local = ~N[2025-06-15 10:00:00]
      path = CanonicalRoutes.post_path(%{id: "abc123", published_at_local: local, name: nil})
      assert path =~ "/posts/abc123/2025/06/15/abc123"
    end

    test "falls back to /posts/:id when published_at_local is nil" do
      assert CanonicalRoutes.post_path(%{id: "abc123"}) == "/posts/abc123"
    end

    test "returns /posts/:id from bare id" do
      assert CanonicalRoutes.post_path("abc123") == "/posts/abc123"
    end
  end

  # ── Avatar ───────────────────────────────────────────────────────────────────

  describe "avatar_url/1" do
    test "returns identicon URL when no avatar is set" do
      person = %{id: "abc123", avatar: nil}
      url = CanonicalRoutes.avatar_url(person)
      assert url =~ "/identicon/abc123"
    end
  end

  # ── URL/URI helpers ───────────────────────────────────────────────────────────

  describe "person_url/1" do
    test "returns absolute URL for person" do
      url = CanonicalRoutes.person_url(%{id: "abc123", username: "alice"})
      assert url =~ "/@alice"
    end
  end

  describe "person_uri/1" do
    test "returns absolute URI for person from struct" do
      uri = CanonicalRoutes.person_uri(%{id: "abc123"})
      assert uri =~ "/people/abc123"
    end
  end

  describe "person ActivityPub URLs" do
    test "person_inbox_url returns inbox path" do
      url = CanonicalRoutes.person_inbox_url("abc123")
      assert url =~ "/people/abc123/inbox"
    end

    test "person_followers_url returns followers path" do
      url = CanonicalRoutes.person_followers_url("abc123")
      assert url =~ "/people/abc123/followers"
    end

    test "person_following_url returns following path" do
      url = CanonicalRoutes.person_following_url("abc123")
      assert url =~ "/people/abc123/following"
    end

    test "person_outbox_url returns outbox path" do
      url = CanonicalRoutes.person_outbox_url("abc123")
      assert url =~ "/people/abc123/outbox"
    end

    test "person_liked_url returns liked path" do
      url = CanonicalRoutes.person_liked_url("abc123")
      assert url =~ "/people/abc123/liked"
    end
  end

  describe "place_uri/1" do
    test "returns absolute URI for place from struct" do
      uri = CanonicalRoutes.place_uri(%{id: "abc123"})
      assert uri =~ "/places/abc123"
    end

    test "returns absolute URI for place from bare id" do
      uri = CanonicalRoutes.place_uri("abc123")
      assert uri =~ "/places/abc123"
    end
  end

  describe "note_path/1" do
    test "returns /notes/:id" do
      assert CanonicalRoutes.note_path("abc123") == "/notes/abc123"
    end
  end

  describe "note_uri/1" do
    test "returns absolute URI for note" do
      uri = CanonicalRoutes.note_uri("abc123")
      assert uri =~ "/notes/abc123"
    end
  end

  describe "note_url/1" do
    test "returns absolute URL for note" do
      url = CanonicalRoutes.note_url("abc123")
      assert url =~ "/notes/abc123"
    end
  end

  describe "checkin_url/1 and checkin_uri/1" do
    test "checkin_url returns absolute URL for checkin" do
      url = CanonicalRoutes.checkin_url(%{id: "abc123"})
      assert url =~ "/checkins/abc123"
    end

    test "checkin_uri returns absolute URI for checkin from struct" do
      uri = CanonicalRoutes.checkin_uri(%{id: "abc123"})
      assert uri =~ "/checkins/abc123"
    end

    test "checkin_uri returns absolute URI for checkin from bare id" do
      uri = CanonicalRoutes.checkin_uri("abc123")
      assert uri =~ "/checkins/abc123"
    end
  end

  describe "post_url/1 and post_uri/1" do
    test "post_url returns absolute URL for post from struct" do
      url = CanonicalRoutes.post_url(%{id: "abc123"})
      assert url =~ "/posts/abc123"
    end

    test "post_uri returns absolute URI for post from struct" do
      uri = CanonicalRoutes.post_uri(%{id: "abc123"})
      assert uri =~ "/posts/abc123"
    end

    test "post_uri returns absolute URI for post from bare id" do
      uri = CanonicalRoutes.post_uri("abc123")
      assert uri =~ "/posts/abc123"
    end
  end

  describe "like_path/1 and like_uri/1" do
    test "like_path returns /likes/:id" do
      assert CanonicalRoutes.like_path("abc123") == "/likes/abc123"
    end

    test "like_uri returns absolute URI for like" do
      uri = CanonicalRoutes.like_uri("abc123")
      assert uri =~ "/likes/abc123"
    end
  end
end
