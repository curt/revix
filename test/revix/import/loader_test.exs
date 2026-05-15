defmodule Revix.ImportTest do
  use Revix.DataCase, async: false

  require Logger
  import Ecto.Query

  alias Revix.Entries.Entry
  alias Revix.Import
  alias Revix.Media.Image
  alias Revix.Places.Place
  alias Revix.Repo

  @author_uri "http://localhost:4000/u/testperson"
  @base_url "http://localhost:4000"

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_json(dir, filename, payload) do
    path = Path.join(dir, filename)
    File.write!(path, Jason.encode!(payload))
    path
  end

  defp export(type, records) do
    %{
      "source" => "klaxon",
      "type" => type,
      "exported_at" => "2024-01-01T00:00:00+00:00",
      "records" => records
    }
  end

  defp place_record(id \\ "klaxon-place-1") do
    %{
      "source_id" => id,
      "title" => "Test Place",
      "slug" => "test-place",
      "lat" => 40.0,
      "lon" => -105.0,
      "ele" => 1600.0,
      "content" => "A great spot",
      "published_at" => "2024-03-01T10:00:00+00:00"
    }
  end

  defp image_record(id \\ "klaxon-media-1") do
    %{
      "source_id" => id,
      "uri" => nil,
      "mime_type" => "image/jpeg",
      "description" => "A photo",
      "original_filename" => nil
    }
  end

  defp checkin_record(id \\ "klaxon-checkin-1", place_id \\ "klaxon-place-1") do
    %{
      "source_id" => id,
      "place_source_id" => place_id,
      "checked_in_at" => "2024-04-01T08:00:00+00:00",
      "published_at" => "2024-04-01T09:00:00+00:00",
      "content" => "great visit",
      "image_source_ids" => []
    }
  end

  defp post_record(id \\ "klaxon-post-1") do
    %{
      "source_id" => id,
      "title" => "Hello World",
      "slug" => "hello-world",
      "content" => "body text",
      "lat" => nil,
      "lon" => nil,
      "place_source_id" => nil,
      "in_reply_to_uri" => nil,
      "context_uri" => nil,
      "published_at" => "2024-05-01T12:00:00+00:00",
      "image_source_ids" => []
    }
  end

  defp located_post_record(id) do
    %{
      "source_id" => id,
      "title" => "Summit Post",
      "slug" => nil,
      "content" => "at the top",
      "lat" => 40.0,
      "lon" => -105.0,
      "place_source_id" => id,
      "in_reply_to_uri" => nil,
      "context_uri" => nil,
      "published_at" => "2024-05-01T12:00:00+00:00",
      "image_source_ids" => []
    }
  end

  # ---------------------------------------------------------------------------
  # import_places/2
  # ---------------------------------------------------------------------------

  describe "import_places/2" do
    test "inserts a place into the DB", %{tmp_dir: dir} do
      write_json(dir, "places.json", export("places", [place_record()]))

      {:places, count} = Import.import_places(dir, base_url: @base_url)
      assert count == 1

      place = Repo.get_by!(Place, name: "Test Place")
      assert place.name == "Test Place"
      assert place.origin == :local
      assert place.slug == "test-place"
      assert place.altitude == 1600.0
    end

    test "generates slug from title when slug is nil", %{tmp_dir: dir} do
      record = Map.put(place_record(), "slug", nil)
      write_json(dir, "places.json", export("places", [record]))
      Import.import_places(dir, base_url: @base_url)

      place = Repo.get_by!(Place, name: "Test Place")
      assert place.slug == "test-place"
    end

    test "generates HTML from Markdown content", %{tmp_dir: dir} do
      record = %{place_record() | "content" => "**bold** text"}
      write_json(dir, "places.json", export("places", [record]))
      Import.import_places(dir, base_url: @base_url)

      place = Repo.get_by!(Place, name: "Test Place")
      assert place.content_html =~ "<strong>bold</strong>"
    end

    test "content_html is nil when content is nil", %{tmp_dir: dir} do
      record = Map.put(place_record(), "content", nil)
      write_json(dir, "places.json", export("places", [record]))
      Import.import_places(dir, base_url: @base_url)

      place = Repo.get_by!(Place, name: "Test Place")
      assert is_nil(place.content_html)
    end

    test "generates a deterministic ID and URI", %{tmp_dir: dir} do
      write_json(dir, "places.json", export("places", [place_record("my-place")]))
      Import.import_places(dir, base_url: @base_url)

      expected_id = Revix.Import.IdUtils.generate_id("my-place")
      place = Repo.get(Place, expected_id)
      assert place
      assert place.uri == "#{@base_url}/places/#{expected_id}"
    end

    test "skips existing places and logs at info level", %{tmp_dir: dir} do
      import ExUnit.CaptureLog

      write_json(dir, "places.json", export("places", [place_record("my-place")]))
      Import.import_places(dir, base_url: @base_url)

      expected_id = Revix.Import.IdUtils.generate_id("my-place")

      log =
        capture_log([level: :info], fn ->
          Logger.configure(level: :info)
          Import.import_places(dir, base_url: @base_url)
          Logger.configure(level: :warning)
        end)

      assert Repo.aggregate("places", :count) == 1
      assert log =~ "import places: #{expected_id} already exists, skipping"
    end

    test "does not overwrite existing place data on re-run", %{tmp_dir: dir} do
      write_json(dir, "places.json", export("places", [place_record()]))
      Import.import_places(dir, base_url: @base_url)

      modified = Map.put(place_record(), "title", "Changed Name")
      write_json(dir, "places.json", export("places", [modified]))
      Import.import_places(dir, base_url: @base_url)

      place = Repo.get_by!(Place, name: "Test Place")
      assert place.name == "Test Place"
    end

    test "dry_run: true does not insert", %{tmp_dir: dir} do
      write_json(dir, "places.json", export("places", [place_record()]))
      {:places, 1} = Import.import_places(dir, base_url: @base_url, dry_run: true)

      assert Repo.aggregate("places", :count) == 0
    end

    test "inserts multiple places", %{tmp_dir: dir} do
      write_json(
        dir,
        "places.json",
        export("places", [place_record("p1"), place_record("p2"), place_record("p3")])
      )

      {:places, 3} = Import.import_places(dir, base_url: @base_url)
      assert Repo.aggregate("places", :count) == 3
    end

    test "writes places_imported.json with revix:id and revix:uri", %{tmp_dir: dir} do
      write_json(dir, "places.json", export("places", [place_record("my-place")]))
      Import.import_places(dir, base_url: @base_url)

      output = dir |> Path.join("places_imported.json") |> File.read!() |> Jason.decode!()
      assert output["type"] == "places"
      [record] = output["records"]
      expected_id = Revix.Import.IdUtils.generate_id("my-place")
      assert record["revix:id"] == expected_id
      assert record["revix:uri"] == "#{@base_url}/places/#{expected_id}"
    end

    test "writes places_imported.json even in dry_run mode", %{tmp_dir: dir} do
      write_json(dir, "places.json", export("places", [place_record("my-place")]))
      Import.import_places(dir, base_url: @base_url, dry_run: true)

      assert File.exists?(Path.join(dir, "places_imported.json"))
      output = dir |> Path.join("places_imported.json") |> File.read!() |> Jason.decode!()
      [record] = output["records"]
      assert record["revix:id"] == Revix.Import.IdUtils.generate_id("my-place")
    end
  end

  # ---------------------------------------------------------------------------
  # import_images/2
  # ---------------------------------------------------------------------------

  describe "import_images/2" do
    test "inserts an image record with placeholder when uri is nil", %{tmp_dir: dir} do
      write_json(dir, "images.json", export("images", [image_record()]))

      {:images, 1} = Import.import_images(dir, author_uri: @author_uri)

      image = Repo.get_by!(Image, author_uri: @author_uri)
      assert image.alt == "A photo"
      assert image.caption == "A photo"
      assert image.caption_html =~ "<p>"
      assert image.content_type == "image/jpeg"
      # Waffle deserializes "" into a struct with file_name: ""
      assert image.file.file_name == ""
    end

    test "nil description produces nil alt, caption, and caption_html", %{tmp_dir: dir} do
      record = Map.put(image_record(), "description", nil)
      write_json(dir, "images.json", export("images", [record]))
      Import.import_images(dir, author_uri: @author_uri)

      image = Repo.get_by!(Image, author_uri: @author_uri)
      assert is_nil(image.alt)
      assert is_nil(image.caption)
      assert is_nil(image.caption_html)
    end

    test "empty string description produces nil alt, caption, and caption_html", %{tmp_dir: dir} do
      record = Map.put(image_record(), "description", "")
      write_json(dir, "images.json", export("images", [record]))
      Import.import_images(dir, author_uri: @author_uri)

      image = Repo.get_by!(Image, author_uri: @author_uri)
      assert is_nil(image.alt)
      assert is_nil(image.caption)
      assert is_nil(image.caption_html)
    end

    test "attempts to download image when URI is set and creates a row", %{tmp_dir: dir} do
      import ExUnit.CaptureLog

      jpeg_body =
        <<0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0>>

      Req.Test.stub(:import, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.send_resp(200, jpeg_body)
      end)

      record = %{image_record() | "uri" => "http://example.com/photo.jpg"}
      write_json(dir, "images.json", export("images", [record]))

      Req.Test.allow(:import, self(), self())
      capture_log(fn -> {:images, 1} = Import.import_images(dir, author_uri: @author_uri) end)

      # Row is created regardless — either via Waffle (valid file) or placeholder fallback
      assert Repo.get_by(Image, author_uri: @author_uri)
    end

    test "falls back to placeholder on 404", %{tmp_dir: dir} do
      Req.Test.stub(:import, fn conn ->
        Plug.Conn.send_resp(conn, 404, "not found")
      end)

      record = %{image_record() | "uri" => "http://example.com/missing.jpg"}
      write_json(dir, "images.json", export("images", [record]))

      Req.Test.allow(:import, self(), self())

      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          {:images, 1} = Import.import_images(dir, author_uri: @author_uri)
        end)

      assert log =~ "HTTP 404"
      image = Repo.get_by!(Image, author_uri: @author_uri)
      assert image.file.file_name == ""
    end

    test "falls back to placeholder on network error", %{tmp_dir: dir} do
      Req.Test.stub(:import, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      record = %{image_record() | "uri" => "http://example.com/photo.jpg"}
      write_json(dir, "images.json", export("images", [record]))

      Req.Test.allow(:import, self(), self())

      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          {:images, 1} = Import.import_images(dir, author_uri: @author_uri)
        end)

      assert log =~ "fetch error"
      image = Repo.get_by!(Image, author_uri: @author_uri)
      assert image.file.file_name == ""
    end

    test "assigns the correct author_uri", %{tmp_dir: dir} do
      write_json(dir, "images.json", export("images", [image_record()]))
      Import.import_images(dir, author_uri: @author_uri)

      image = Repo.get_by!(Image, author_uri: @author_uri)
      assert image.author_uri == @author_uri
    end

    test "skips existing images and logs at info level", %{tmp_dir: dir} do
      import ExUnit.CaptureLog

      write_json(dir, "images.json", export("images", [image_record("img-skip")]))
      Import.import_images(dir, author_uri: @author_uri)

      expected_id = Revix.Import.IdUtils.generate_id("img-skip")

      log =
        capture_log([level: :info], fn ->
          Logger.configure(level: :info)
          Import.import_images(dir, author_uri: @author_uri)
          Logger.configure(level: :warning)
        end)

      assert Repo.aggregate("images", :count) == 1
      assert log =~ "import_images: image #{expected_id} already exists, skipping"
    end

    test "dry_run: true does not insert", %{tmp_dir: dir} do
      write_json(dir, "images.json", export("images", [image_record()]))
      {:images, 1} = Import.import_images(dir, author_uri: @author_uri, dry_run: true)

      assert Repo.aggregate("images", :count) == 0
    end

    test "writes images_imported.json with revix:id", %{tmp_dir: dir} do
      write_json(dir, "images.json", export("images", [image_record("img-abc")]))
      Import.import_images(dir, author_uri: @author_uri)

      output = dir |> Path.join("images_imported.json") |> File.read!() |> Jason.decode!()
      assert output["type"] == "images"
      [record] = output["records"]
      assert record["revix:id"] == Revix.Import.IdUtils.generate_id("img-abc")
      refute Map.has_key?(record, "revix:uri")
    end

    test "writes images_imported.json even in dry_run mode", %{tmp_dir: dir} do
      write_json(dir, "images.json", export("images", [image_record("img-abc")]))
      Import.import_images(dir, author_uri: @author_uri, dry_run: true)

      assert File.exists?(Path.join(dir, "images_imported.json"))
    end
  end

  # ---------------------------------------------------------------------------
  # import_checkins/2
  # ---------------------------------------------------------------------------

  describe "import_checkins/2" do
    test "inserts a checkin entry", %{tmp_dir: dir} do
      write_json(dir, "checkins.json", export("checkins", [checkin_record()]))

      {:checkins, 1} = Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri)

      entry = Repo.get_by!(Entry, type: :checkin)
      assert entry.type == :checkin
      assert entry.origin == :local
      assert entry.author_uri == @author_uri
      assert entry.content == "great visit"
    end

    test "generates HTML from Markdown content", %{tmp_dir: dir} do
      record = %{checkin_record() | "content" => "# Heading"}
      write_json(dir, "checkins.json", export("checkins", [record]))
      Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri)

      entry = Repo.get_by!(Entry, type: :checkin)
      assert entry.content_html =~ "<h1>"
    end

    test "URI is constructed with /checkins/ prefix", %{tmp_dir: dir} do
      write_json(dir, "checkins.json", export("checkins", [checkin_record("c1", "p1")]))
      Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri)

      checkin_id = Revix.Import.IdUtils.generate_id("c1")
      place_id = Revix.Import.IdUtils.generate_id("p1")

      entry = Repo.get(Entry, checkin_id)
      assert entry.uri == "#{@base_url}/checkins/#{checkin_id}"
      assert entry.place_uri == "#{@base_url}/places/#{place_id}"
    end

    test "three-part datetime fields are populated", %{tmp_dir: dir} do
      write_json(dir, "checkins.json", export("checkins", [checkin_record()]))
      Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri)

      entry = Repo.get_by!(Entry, type: :checkin)
      assert entry.starts_at_utc
      assert entry.starts_at_local
      assert entry.starts_tz == "Etc/UTC"
      assert entry.published_at_utc
      assert entry.published_tz == "Etc/UTC"
    end

    test "skips existing checkins and logs at info level", %{tmp_dir: dir} do
      import ExUnit.CaptureLog

      write_json(dir, "checkins.json", export("checkins", [checkin_record("c1", "p1")]))
      Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri)

      expected_id = Revix.Import.IdUtils.generate_id("c1")

      log =
        capture_log([level: :info], fn ->
          Logger.configure(level: :info)
          Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri)
          Logger.configure(level: :warning)
        end)

      assert Repo.aggregate("entries", :count) == 1
      assert log =~ "import entries: #{expected_id} already exists, skipping"
    end

    test "does not overwrite existing checkin data on re-run", %{tmp_dir: dir} do
      write_json(dir, "checkins.json", export("checkins", [checkin_record()]))
      Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri)

      modified = Map.put(checkin_record(), "content", "changed content")
      write_json(dir, "checkins.json", export("checkins", [modified]))
      Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri)

      entry = Repo.get_by!(Entry, type: :checkin)
      assert entry.content == "great visit"
    end

    test "dry_run: true does not insert", %{tmp_dir: dir} do
      write_json(dir, "checkins.json", export("checkins", [checkin_record()]))

      {:checkins, 1} =
        Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri, dry_run: true)

      assert Repo.aggregate("entries", :count) == 0
    end

    test "inserts entry_images for attached images", %{tmp_dir: dir} do
      write_json(
        dir,
        "images.json",
        export("images", [image_record("img1"), image_record("img2")])
      )

      Import.import_images(dir, author_uri: @author_uri)

      checkin = %{checkin_record() | "image_source_ids" => ["img1", "img2"]}
      write_json(dir, "checkins.json", export("checkins", [checkin]))
      Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri)

      assert Repo.aggregate("entry_images", :count) == 2
    end

    test "entry_images have correct positions", %{tmp_dir: dir} do
      write_json(
        dir,
        "images.json",
        export("images", [image_record("img1"), image_record("img2")])
      )

      Import.import_images(dir, author_uri: @author_uri)

      checkin = %{checkin_record() | "image_source_ids" => ["img1", "img2"]}
      write_json(dir, "checkins.json", export("checkins", [checkin]))
      Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri)

      positions =
        Repo.all(from(ei in "entry_images", select: ei.position)) |> Enum.sort()

      assert positions == [0, 1]
    end

    test "writes checkins_imported.json with revix:id and revix:uri", %{tmp_dir: dir} do
      write_json(dir, "checkins.json", export("checkins", [checkin_record("c1", "p1")]))
      Import.import_checkins(dir, base_url: @base_url, author_uri: @author_uri)

      output = dir |> Path.join("checkins_imported.json") |> File.read!() |> Jason.decode!()
      [record] = output["records"]
      checkin_id = Revix.Import.IdUtils.generate_id("c1")
      assert record["revix:id"] == checkin_id
      assert record["revix:uri"] == "#{@base_url}/checkins/#{checkin_id}"
    end
  end

  # ---------------------------------------------------------------------------
  # import_posts/2
  # ---------------------------------------------------------------------------

  describe "import_posts/2" do
    test "inserts a post as an entry of type 'post'", %{tmp_dir: dir} do
      write_json(dir, "posts.json", export("posts", [post_record()]))

      {:posts, 1} = Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri)

      entry = Repo.get_by!(Entry, type: :post)
      assert entry.type == :post
      assert entry.name == "Hello World"
      assert entry.content == "body text"
      assert entry.author_uri == @author_uri
    end

    test "generates HTML from Markdown content", %{tmp_dir: dir} do
      record = %{post_record() | "content" => "- item one\n- item two"}
      write_json(dir, "posts.json", export("posts", [record]))
      Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri)

      entry = Repo.get_by!(Entry, type: :post)
      assert entry.content_html =~ "<li>"
    end

    test "URI is constructed with /posts/ prefix", %{tmp_dir: dir} do
      write_json(dir, "posts.json", export("posts", [post_record("post1")]))
      Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri)

      post_id = Revix.Import.IdUtils.generate_id("post1")
      entry = Repo.get(Entry, post_id)
      assert entry.uri == "#{@base_url}/posts/#{post_id}"
      assert is_nil(entry.place_uri)
    end

    test "post with place_source_id gets /posts/ URI and place_uri", %{tmp_dir: dir} do
      write_json(dir, "posts.json", export("posts", [located_post_record("post-loc")]))
      Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri)

      post_id = Revix.Import.IdUtils.generate_id("post-loc")
      place_id = Revix.Import.IdUtils.generate_id("post-loc")
      entry = Repo.get(Entry, post_id)
      assert entry.uri == "#{@base_url}/posts/#{post_id}"
      assert entry.place_uri == "#{@base_url}/places/#{place_id}"
    end

    test "in_reply_to_uri is preserved", %{tmp_dir: dir} do
      post = %{post_record() | "in_reply_to_uri" => "http://example.com/notes/xyz"}
      write_json(dir, "posts.json", export("posts", [post]))
      Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri)

      entry = Repo.get_by!(Entry, type: :post)
      assert entry.in_reply_to_uri == "http://example.com/notes/xyz"
    end

    test "skips existing posts and logs at info level", %{tmp_dir: dir} do
      import ExUnit.CaptureLog

      write_json(dir, "posts.json", export("posts", [post_record("post1")]))
      Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri)

      expected_id = Revix.Import.IdUtils.generate_id("post1")

      log =
        capture_log([level: :info], fn ->
          Logger.configure(level: :info)
          Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri)
          Logger.configure(level: :warning)
        end)

      assert Repo.aggregate("entries", :count) == 1
      assert log =~ "import entries: #{expected_id} already exists, skipping"
    end

    test "does not overwrite existing post data on re-run", %{tmp_dir: dir} do
      write_json(dir, "posts.json", export("posts", [post_record()]))
      Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri)

      modified = Map.put(post_record(), "content", "changed content")
      write_json(dir, "posts.json", export("posts", [modified]))
      Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri)

      entry = Repo.get_by!(Entry, type: :post)
      assert entry.content == "body text"
    end

    test "dry_run: true does not insert", %{tmp_dir: dir} do
      write_json(dir, "posts.json", export("posts", [post_record()]))

      {:posts, 1} =
        Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri, dry_run: true)

      assert Repo.aggregate("entries", :count) == 0
    end

    test "inserts entry_images for attached images", %{tmp_dir: dir} do
      write_json(dir, "images.json", export("images", [image_record("img3")]))
      Import.import_images(dir, author_uri: @author_uri)

      post = %{post_record() | "image_source_ids" => ["img3"]}
      write_json(dir, "posts.json", export("posts", [post]))
      Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri)

      assert Repo.aggregate("entry_images", :count) == 1
    end

    test "writes posts_imported.json with revix:id and revix:uri", %{tmp_dir: dir} do
      write_json(dir, "posts.json", export("posts", [post_record("post1")]))
      Import.import_posts(dir, base_url: @base_url, author_uri: @author_uri)

      output = dir |> Path.join("posts_imported.json") |> File.read!() |> Jason.decode!()
      [record] = output["records"]
      post_id = Revix.Import.IdUtils.generate_id("post1")
      assert record["revix:id"] == post_id
      assert record["revix:uri"] == "#{@base_url}/posts/#{post_id}"
    end
  end

  # ---------------------------------------------------------------------------
  # import_all/2
  # ---------------------------------------------------------------------------

  describe "import_all/2" do
    test "imports all four entity types in the correct order", %{tmp_dir: dir} do
      write_json(dir, "places.json", export("places", [place_record()]))
      write_json(dir, "images.json", export("images", [image_record()]))
      write_json(dir, "checkins.json", export("checkins", [checkin_record()]))
      write_json(dir, "posts.json", export("posts", [post_record()]))

      :ok =
        Import.import_all(dir,
          base_url: @base_url,
          author_uri: @author_uri
        )

      assert Repo.aggregate("places", :count) == 1
      assert Repo.aggregate("images", :count) == 1
      assert Repo.aggregate("entries", :count) == 2
    end

    test "dry_run: true imports nothing", %{tmp_dir: dir} do
      write_json(dir, "places.json", export("places", [place_record()]))
      write_json(dir, "images.json", export("images", [image_record()]))
      write_json(dir, "checkins.json", export("checkins", [checkin_record()]))
      write_json(dir, "posts.json", export("posts", [post_record()]))

      Import.import_all(dir,
        base_url: @base_url,
        author_uri: @author_uri,
        dry_run: true
      )

      assert Repo.aggregate("places", :count) == 0
      assert Repo.aggregate("images", :count) == 0
      assert Repo.aggregate("entries", :count) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # DataCase tmp_dir setup
  # ---------------------------------------------------------------------------

  setup do
    dir = System.tmp_dir!() |> Path.join("klaxon_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, tmp_dir: dir}
  end
end
