defmodule Revix.Import do
  require Logger

  import Ecto.Query

  alias Revix.Import.IdUtils
  alias Revix.Media.Image
  alias Revix.Repo

  @doc """
  Imports all four entity types from a folder of JSON export files conforming
  to the revix_import.json schema. Call from `iex` after mounting the export
  folder:

      Revix.Import.import_all("/path/to/export",
        base_url: "https://example.com",
        author_uri: "https://example.com/u/PERSON_ID"
      )

  Options:
    - `:base_url` — base URL used to construct URIs (default: "http://localhost:4000")
    - `:author_uri` — required URI of the Revix person who owns the imported content
    - `:dry_run` — if `true`, logs counts but does not write to the DB (default: false)
  """
  def import_all(folder, opts \\ []) do
    author_uri = Keyword.fetch!(opts, :author_uri)
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")
    dry_run = Keyword.get(opts, :dry_run, false)

    results = [
      import_places(folder, base_url: base_url, dry_run: dry_run),
      import_images(folder, author_uri: author_uri, dry_run: dry_run),
      import_checkins(folder, base_url: base_url, author_uri: author_uri, dry_run: dry_run),
      import_posts(folder, base_url: base_url, author_uri: author_uri, dry_run: dry_run)
    ]

    for {type, count} <- results do
      Logger.info(
        "import_all: #{type} — #{count} records#{if dry_run, do: " (dry run)", else: ""}"
      )
    end

    :ok
  end

  @doc """
  Imports places from `places.json` in `folder`.
  """
  def import_places(folder, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")
    dry_run = Keyword.get(opts, :dry_run, false)
    now = DateTime.utc_now(:second)

    raw = read_json(folder, "places.json")

    records =
      Enum.map(raw, fn r ->
        id = IdUtils.generate_id(r["source_id"])
        uri = "#{base_url}/places/#{id}"

        %{
          id: id,
          uri: uri,
          url: uri,
          origin: "local",
          name: r["title"],
          slug: r["slug"] || Slug.slugify(r["title"]),
          altitude: r["ele"],
          content: r["content"],
          content_html: markdown_to_html(r["content"]),
          coordinates: build_point(r["lon"], r["lat"]),
          inserted_at: parse_datetime(r["published_at"]) || now,
          updated_at: now
        }
      end)

    unless dry_run do
      log_existing("places", records)
      Repo.insert_all("places", records, on_conflict: :nothing, conflict_target: :id)
    end

    annotated =
      Enum.map(Enum.zip(raw, records), fn {r, rec} ->
        Map.merge(r, %{"revix:id" => rec.id, "revix:uri" => rec.uri})
      end)

    write_imported(folder, "places_imported.json", "places", annotated)

    {:places, length(records)}
  end

  @doc """
  Imports image metadata from `images.json` in `folder`. For each image with a
  URI, attempts to download the file and store it via the Waffle pipeline. On
  failure (non-200, network error, unrecognised type), creates the row with an
  empty file placeholder so entry_images FK references still resolve.
  """
  def import_images(folder, opts \\ []) do
    author_uri = Keyword.fetch!(opts, :author_uri)
    dry_run = Keyword.get(opts, :dry_run, false)
    now = DateTime.utc_now(:second)

    raw = read_json(folder, "images.json")

    ids = Enum.map(raw, fn r -> IdUtils.generate_id(r["source_id"]) end)

    unless dry_run do
      existing_ids = Repo.all(from i in "images", where: i.id in ^ids, select: i.id)

      Enum.zip(raw, ids)
      |> Enum.each(fn {r, id} ->
        if id in existing_ids do
          Logger.info("import_images: image #{id} already exists, skipping")
        else
          import_one_image(r, id, author_uri, now)
        end
      end)
    end

    annotated =
      Enum.map(Enum.zip(raw, ids), fn {r, id} ->
        Map.put(r, "revix:id", id)
      end)

    write_imported(folder, "images_imported.json", "images", annotated)

    {:images, length(raw)}
  end

  @doc """
  Imports checkins from `checkins.json` in `folder` as entries of type `:checkin`,
  then inserts entry_images join rows for any attached images.
  """
  def import_checkins(folder, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")
    author_uri = Keyword.fetch!(opts, :author_uri)
    dry_run = Keyword.get(opts, :dry_run, false)
    now = DateTime.utc_now(:second)

    raw = read_json(folder, "checkins.json")

    entries =
      Enum.map(raw, fn r ->
        id = IdUtils.generate_id(r["source_id"])
        place_id = IdUtils.generate_id(r["place_source_id"])
        uri = "#{base_url}/checkins/#{id}"
        starts_utc = parse_datetime(r["checked_in_at"])
        published_utc = parse_datetime(r["published_at"])

        %{
          id: id,
          uri: uri,
          url: uri,
          type: "checkin",
          origin: "local",
          content: r["content"],
          content_html: markdown_to_html(r["content"]),
          starts_at_utc: starts_utc,
          starts_at_local: to_naive(starts_utc),
          starts_tz: "Etc/UTC",
          published_at_utc: published_utc,
          published_at_local: to_naive(published_utc),
          published_tz: "Etc/UTC",
          author_uri: author_uri,
          place_uri: "#{base_url}/places/#{place_id}",
          context: uri,
          inserted_at: now,
          updated_at: now
        }
      end)

    entry_images = build_entry_images(raw, fn r -> IdUtils.generate_id(r["source_id"]) end, now)

    unless dry_run do
      log_existing("entries", entries)
      Repo.insert_all("entries", entries, on_conflict: :nothing, conflict_target: :id)

      Repo.insert_all("entry_images", entry_images,
        on_conflict: :nothing,
        conflict_target: [:entry_id, :image_id]
      )
    end

    annotated =
      Enum.map(Enum.zip(raw, entries), fn {r, entry} ->
        Map.merge(r, %{"revix:id" => entry.id, "revix:uri" => entry.uri})
      end)

    write_imported(folder, "checkins_imported.json", "checkins", annotated)

    {:checkins, length(entries)}
  end

  @doc """
  Imports posts from `posts.json` in `folder` as entries of type `:note`,
  then inserts entry_images join rows for any attached images.
  """
  def import_posts(folder, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")
    author_uri = Keyword.fetch!(opts, :author_uri)
    dry_run = Keyword.get(opts, :dry_run, false)
    now = DateTime.utc_now(:second)

    raw = read_json(folder, "posts.json")

    entries =
      Enum.map(raw, fn r ->
        id = IdUtils.generate_id(r["source_id"])
        published_utc = parse_datetime(r["published_at"])
        {uri, place_uri} = build_post_uris(base_url, id, r["place_source_id"])

        %{
          id: id,
          uri: uri,
          url: uri,
          type: "post",
          origin: "local",
          name: r["title"],
          content: r["content"],
          content_html: markdown_to_html(r["content"]),
          in_reply_to_uri: r["in_reply_to_uri"],
          context: r["context_uri"],
          published_at_utc: published_utc,
          published_at_local: to_naive(published_utc),
          published_tz: "Etc/UTC",
          author_uri: author_uri,
          place_uri: place_uri,
          inserted_at: now,
          updated_at: now
        }
      end)

    entry_images = build_entry_images(raw, fn r -> IdUtils.generate_id(r["source_id"]) end, now)

    unless dry_run do
      log_existing("entries", entries)
      Repo.insert_all("entries", entries, on_conflict: :nothing, conflict_target: :id)

      Repo.insert_all("entry_images", entry_images,
        on_conflict: :nothing,
        conflict_target: [:entry_id, :image_id]
      )
    end

    annotated =
      Enum.map(Enum.zip(raw, entries), fn {r, entry} ->
        Map.merge(r, %{"revix:id" => entry.id, "revix:uri" => entry.uri})
      end)

    write_imported(folder, "posts_imported.json", "posts", annotated)

    {:posts, length(entries)}
  end

  defp import_one_image(r, id, author_uri, now) do
    uri = r["uri"]
    description = presence(r["description"])

    attrs = %{
      alt: description,
      caption: description,
      caption_html: markdown_to_html(description),
      content_type: r["mime_type"],
      original_filename: r["original_filename"],
      author_uri: author_uri
    }

    if uri do
      fetch_and_store_image(id, uri, attrs, now)
    else
      insert_image_placeholder(id, attrs, now)
    end
  end

  defp fetch_and_store_image(id, uri, attrs, now) do
    req_opts = build_req_opts()

    case Req.get(uri, req_opts) do
      {:ok, %{status: 200, body: body}} ->
        store_image_with_file(id, body, attrs, now)

      {:ok, %{status: status}} ->
        Logger.warning("import_images: HTTP #{status} for #{uri}")
        insert_image_placeholder(id, attrs, now)

      {:error, reason} ->
        Logger.warning("import_images: fetch error for #{uri}: #{inspect(reason)}")
        insert_image_placeholder(id, attrs, now)
    end
  end

  defp store_image_with_file(id, body, attrs, _now) do
    case ExImageInfo.seems?(body) do
      nil ->
        Logger.warning("import_images: unrecognised image type for id #{id}")
        insert_image_placeholder(id, attrs, nil)

      type ->
        ext = if type == :jpeg, do: "jpg", else: Atom.to_string(type)
        upload = %{filename: "original.#{ext}", binary: body}

        result =
          %Image{id: id}
          |> Image.changeset(Map.put(attrs, :file, upload))
          |> Repo.insert(on_conflict: :nothing, conflict_target: :id)

        case result do
          {:ok, _} = ok ->
            ok

          {:error, reason} ->
            Logger.warning("import_images: Waffle error for id #{id}: #{inspect(reason)}")
            insert_image_placeholder(id, attrs, nil)
        end
    end
  end

  defp insert_image_placeholder(id, attrs, now) do
    now = now || DateTime.utc_now(:second)

    row = %{
      id: id,
      file: "",
      alt: attrs.alt,
      caption: attrs.caption,
      caption_html: attrs.caption_html,
      content_type: attrs.content_type,
      original_filename: attrs.original_filename,
      author_uri: attrs.author_uri,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all("images", [row], on_conflict: :nothing, conflict_target: :id)
    {:ok, :placeholder}
  end

  defp build_post_uris(base_url, id, nil),
    do: {"#{base_url}/posts/#{id}", nil}

  defp build_post_uris(base_url, id, place_source_id) do
    place_id = IdUtils.generate_id(place_source_id)
    {"#{base_url}/posts/#{id}", "#{base_url}/places/#{place_id}"}
  end

  defp build_req_opts do
    plug = Application.get_env(:revix, :import_req_plug)
    base = [retry: false, decode_body: false]
    if plug, do: Keyword.put(base, :plug, plug), else: base
  end

  defp read_json(folder, filename) do
    path = Path.join(folder, filename)
    path |> File.read!() |> Jason.decode!() |> Map.fetch!("records")
  end

  defp write_imported(folder, filename, type, records) do
    envelope = %{
      source: "revix-import",
      type: type,
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      records: records
    }

    path = Path.join(folder, filename)
    File.write!(path, Jason.encode!(envelope, pretty: true))
  end

  defp log_existing(table, records) do
    batch_ids = Enum.map(records, & &1.id)
    existing_ids = Repo.all(from r in table, where: r.id in ^batch_ids, select: r.id)

    Enum.each(existing_ids, fn id ->
      Logger.info("import #{table}: #{id} already exists, skipping")
    end)
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(str), do: str

  defp markdown_to_html(nil), do: nil

  defp markdown_to_html(md) do
    case Earmark.as_html(md, compact_output: true) do
      {:ok, html, _} -> html
      _ -> nil
    end
  end

  defp build_point(lon, lat) when is_number(lon) and is_number(lat) do
    %Geo.Point{coordinates: {lon, lat}, srid: 4326}
  end

  defp build_point(_, _), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp to_naive(nil), do: nil
  defp to_naive(%DateTime{} = dt), do: DateTime.to_naive(dt)

  defp build_entry_images(records, id_fn, now) do
    Enum.flat_map(records, fn r ->
      entry_id = id_fn.(r)

      (r["image_source_ids"] || [])
      |> Enum.with_index()
      |> Enum.map(fn {image_source_id, position} ->
        image_id = IdUtils.generate_id(image_source_id)
        ei_id = IdUtils.generate_id("#{entry_id}:#{image_id}")

        %{
          id: ei_id,
          entry_id: entry_id,
          image_id: image_id,
          position: position,
          inserted_at: now,
          updated_at: now
        }
      end)
    end)
  end
end
