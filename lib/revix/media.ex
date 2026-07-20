defmodule Revix.Media do
  require Logger

  import Ecto.Query
  alias Revix.Repo
  alias Revix.Media.Image
  alias Revix.Media.EntryImage
  alias Revix.Media.ImageDimension

  def create_image(attrs) do
    id = Revix.Ecto.Base58Id.autogenerate()

    case %Image{id: id} |> Image.changeset(attrs) |> Repo.insert() do
      {:ok, image} ->
        capture_dimensions(image)
        {:ok, image}

      error ->
        error
    end
  end

  def get_image(id) do
    case Repo.get(Image, id) do
      nil -> {:error, :not_found}
      image -> {:ok, image}
    end
  end

  def delete_image(%Image{} = image) do
    Revix.Uploaders.Image.delete({image.file, image})
    Repo.delete(image)
  end

  def attach_image_to_entry(entry_id, image_id, position) do
    id = Revix.Ecto.Base58Id.autogenerate()

    %EntryImage{id: id}
    |> EntryImage.changeset(%{entry_id: entry_id, image_id: image_id, position: position})
    |> Repo.insert()
  end

  def get_images_for_entry(entry_id) do
    Repo.all(
      from(ei in EntryImage,
        where: ei.entry_id == ^entry_id,
        order_by: [asc: ei.position],
        preload: [:image]
      )
    )
    |> Enum.map(& &1.image)
  end

  def update_image(%Image{} = image, attrs) do
    image
    |> Image.update_changeset(attrs)
    |> Repo.update()
  end

  def update_entry_image_position(entry_id, image_id, position) do
    Repo.update_all(
      from(ei in EntryImage,
        where: ei.entry_id == ^entry_id and ei.image_id == ^image_id
      ),
      set: [position: position]
    )
  end

  def remove_image_from_entry(entry_id, image_id) do
    case detach_image(entry_id, image_id) do
      :detached -> maybe_delete_orphaned_image(image_id)
      :not_found -> :ok
    end
  end

  defp detach_image(entry_id, image_id) do
    entry_image =
      Repo.one(
        from(ei in EntryImage,
          where: ei.entry_id == ^entry_id and ei.image_id == ^image_id
        )
      )

    if entry_image do
      Repo.delete(entry_image)
      :detached
    else
      :not_found
    end
  end

  defp maybe_delete_orphaned_image(image_id) do
    remaining =
      Repo.aggregate(from(ei in EntryImage, where: ei.image_id == ^image_id), :count)

    if remaining == 0 do
      case get_image(image_id) do
        {:ok, image} -> delete_image(image)
        _ -> :ok
      end
    end

    :ok
  end

  def create_and_attach_images(entry_id, author_uri, uploads) when is_list(uploads) do
    uploads
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {upload, index}, {:ok, acc} ->
      attrs = %{
        file: upload,
        author_uri: author_uri,
        content_type: upload.content_type,
        original_filename: upload.filename
      }

      case create_image(attrs) do
        {:ok, image} ->
          case attach_image_to_entry(entry_id, image.id, index) do
            {:ok, _} -> {:cont, {:ok, acc ++ [image]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  def create_and_attach_images(_entry_id, _author_uri, _), do: {:ok, []}

  def retransform_images_for_entry(entry_id) do
    entry_id
    |> get_images_for_entry()
    |> Enum.each(&retransform_image/1)
  end

  defp retransform_image(%Image{} = image) do
    ext = Path.extname(image.original_filename)
    temp = Waffle.File.generate_temporary_path(ext)

    Logger.info("[retransform] starting image #{image.id} (#{image.original_filename})")

    result =
      with {:ok, binary} <- fetch_original_binary(image, ext),
           _ =
             Logger.info(
               "[retransform] fetched original for #{image.id} (#{byte_size(binary)} bytes)"
             ),
           :ok <- File.write(temp, binary),
           {:ok, _} <-
             Revix.Uploaders.Image.store({%{filename: "original#{ext}", path: temp}, image}),
           {:ok, updated} <- touch_image_timestamp(image) do
        capture_dimensions(updated)
        {:ok, updated}
      end

    File.rm(temp)

    case result do
      {:ok, _} ->
        Logger.info("[retransform] finished image #{image.id}")

      err ->
        Logger.error("[retransform] failed for image #{image.id}: #{inspect(err)}")
    end

    result
  end

  defp fetch_original_binary(%Image{id: id}, ext), do: read_stored_file(id, "original#{ext}")

  defp read_stored_file(image_id, filename) do
    case Application.get_env(:waffle, :storage) do
      Waffle.Storage.S3 ->
        bucket = Application.get_env(:waffle, :bucket)
        key = "uploads/images/#{image_id}/#{filename}"

        case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
          {:ok, %{body: binary}} -> {:ok, binary}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        prefix = Application.get_env(:waffle, :storage_dir_prefix, "priv/waffle/public")
        path = Path.join([prefix, "uploads/images/#{image_id}", filename])
        File.read(path)
    end
  end

  defp touch_image_timestamp(%Image{} = image) do
    image
    |> Ecto.Changeset.change(
      file: %{
        file_name: image.file.file_name,
        updated_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      }
    )
    |> Repo.update()
  end

  defp capture_dimensions(%Image{} = image) do
    Enum.each([:large, :medium], &capture_version_dimensions(image, &1))
  end

  defp capture_version_dimensions(%Image{id: id} = image, version) do
    case read_version_dimensions(id, "#{version}.jpg") do
      {:ok, width, height} ->
        upsert_dimensions(image.id, version, width, height)

      :error ->
        Logger.warning("[dimensions] failed to capture #{version} for image #{id}")
    end
  end

  defp read_version_dimensions(image_id, filename) do
    case Application.get_env(:waffle, :storage) do
      Waffle.Storage.S3 -> read_dimensions_from_s3_metadata(image_id, filename)
      _ -> read_dimensions_from_local_file(image_id, filename)
    end
  end

  defp read_dimensions_from_s3_metadata(image_id, filename) do
    bucket = Application.get_env(:waffle, :bucket)
    key = "uploads/images/#{image_id}/#{filename}"

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

  defp read_dimensions_from_local_file(image_id, filename) do
    case read_stored_file(image_id, filename) do
      {:ok, binary} ->
        case ExImageInfo.info(binary) do
          {_mime, width, height, _variant} -> {:ok, width, height}
          nil -> :error
        end

      {:error, _} ->
        :error
    end
  end

  defp upsert_dimensions(image_id, version, width, height) do
    id = Revix.Ecto.Base58Id.autogenerate()

    %ImageDimension{id: id}
    |> ImageDimension.changeset(%{
      image_id: image_id,
      version: version,
      width: width,
      height: height
    })
    |> Repo.insert(
      on_conflict: {:replace, [:width, :height, :updated_at]},
      conflict_target: [:image_id, :version]
    )
  end
end
