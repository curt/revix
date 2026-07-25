defmodule Revix.Repo.Migrations.BackfillImageDimensions do
  use Ecto.Migration
  require Logger
  import Ecto.Query

  def up do
    ensure_ex_aws_started()

    image_ids = Revix.Repo.all(from(i in "images", select: %{id: i.id}))

    results =
      Enum.flat_map(image_ids, fn %{id: id} ->
        Enum.map(["large", "medium"], fn version -> backfill_version(id, version) end)
      end)

    inserted = Enum.count(results, &(&1 == :inserted))
    skipped = Enum.count(results, &(&1 == :skipped))

    Logger.info(
      "[dimensions backfill] processed #{length(image_ids)} images: " <>
        "#{inserted} rows inserted, #{skipped} skipped"
    )
  end

  def down, do: :ok

  # Release migrations run under Ecto.Migrator.with_repo/2, which starts only
  # the repo's own dependency tree, not the full :revix application — so
  # :ex_aws/:hackney are never started and ExAws.request/1 crashes on a
  # missing :hackney_config ETS table unless we start them ourselves here.
  defp ensure_ex_aws_started do
    if Application.get_env(:waffle, :storage) == Waffle.Storage.S3 do
      {:ok, _} = Application.ensure_all_started(:ex_aws)
    end
  end

  defp backfill_version(image_id, version) do
    filename = "#{version}.jpg"

    case dimensions_for(image_id, filename) do
      {:ok, width, height} ->
        insert_dimension_row(image_id, version, width, height)
        :inserted

      :error ->
        :skipped
    end
  end

  # Cheap path first (HEAD-only, or free for local disk); only pays for a
  # full GET when metadata is missing/incomplete, i.e. genuinely pre-PR-2 images.
  defp dimensions_for(image_id, filename) do
    case Application.get_env(:waffle, :storage) do
      Waffle.Storage.S3 -> dimensions_for_s3(image_id, filename)
      _ -> dimensions_from_local_file(image_id, filename)
    end
  end

  defp dimensions_for_s3(image_id, filename) do
    bucket = Application.get_env(:waffle, :bucket)
    key = "uploads/images/#{image_id}/#{filename}"

    case dimensions_from_s3_metadata(bucket, key) do
      {:ok, width, height} ->
        {:ok, width, height}

      :error ->
        with {:ok, width, height} <- dimensions_from_s3_body(bucket, key) do
          backfill_s3_metadata(bucket, key, width, height)
          {:ok, width, height}
        end
    end
  end

  defp dimensions_from_s3_metadata(bucket, key) do
    case ExAws.S3.head_object(bucket, key) |> ExAws.request() do
      {:ok, %{headers: headers}} -> parse_meta_dimensions(headers)
      {:error, _} -> :error
    end
  end

  defp parse_meta_dimensions(headers) do
    meta = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)

    with width when width != nil <- meta["x-amz-meta-width"],
         height when height != nil <- meta["x-amz-meta-height"],
         {w, ""} <- Integer.parse(width),
         {h, ""} <- Integer.parse(height) do
      {:ok, w, h}
    else
      _ -> :error
    end
  end

  defp dimensions_from_s3_body(bucket, key) do
    with {:ok, %{body: binary}} <- ExAws.S3.get_object(bucket, key) |> ExAws.request(),
         {_mime, width, height, _variant} <- ExImageInfo.info(binary) do
      {:ok, width, height}
    else
      {:error, reason} ->
        Logger.warning("[dimensions backfill] GET failed for #{key}: #{inspect(reason)}")
        :error

      _ ->
        Logger.warning("[dimensions backfill] could not decode image dimensions for #{key}")
        :error
    end
  end

  defp dimensions_from_local_file(image_id, filename) do
    prefix = Application.get_env(:waffle, :storage_dir_prefix, "priv/waffle/public")
    path = Path.join([prefix, "uploads/images/#{image_id}", filename])

    with {:ok, binary} <- File.read(path),
         {_mime, width, height, _variant} <- ExImageInfo.info(binary) do
      {:ok, width, height}
    else
      {:error, reason} ->
        Logger.warning("[dimensions backfill] read failed for #{path}: #{inspect(reason)}")
        :error

      _ ->
        Logger.warning("[dimensions backfill] could not decode image dimensions for #{path}")
        :error
    end
  end

  # Self-copy: updates S3 object metadata in place without re-uploading the
  # body, so a future repair pass can take the cheap HEAD path instead of GET.
  defp backfill_s3_metadata(bucket, key, width, height) do
    case ExAws.S3.put_object_copy(bucket, key, bucket, key,
           metadata_directive: :REPLACE,
           meta: [{"width", to_string(width)}, {"height", to_string(height)}]
         )
         |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[dimensions backfill] metadata write failed for #{key}: #{inspect(reason)}"
        )
    end
  end

  defp insert_dimension_row(image_id, version, width, height) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Revix.Repo.insert_all(
      "image_dimensions",
      [
        %{
          id: Revix.Ecto.Base58Id.autogenerate(),
          image_id: image_id,
          version: version,
          width: width,
          height: height,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:image_id, :version]
    )
  end
end
