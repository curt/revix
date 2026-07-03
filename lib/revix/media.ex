defmodule Revix.Media do
  import Ecto.Query
  alias Revix.Repo
  alias Revix.Media.Image
  alias Revix.Media.EntryImage

  def create_image(attrs) do
    id = Revix.Ecto.Base58Id.autogenerate()

    %Image{id: id}
    |> Image.changeset(attrs)
    |> Repo.insert()
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

    result =
      with {:ok, binary} <- fetch_original_binary(image, ext),
           :ok <- File.write(temp, binary),
           {:ok, _} <-
             Revix.Uploaders.Image.store({%{filename: "original#{ext}", path: temp}, image}) do
        touch_image_timestamp(image)
      end

    File.rm(temp)
    result
  end

  defp fetch_original_binary(%Image{id: id}, ext) do
    case Application.get_env(:waffle, :storage) do
      Waffle.Storage.S3 ->
        bucket = Application.get_env(:waffle, :bucket)
        key = "uploads/images/#{id}/original#{ext}"

        case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
          {:ok, %{body: binary}} -> {:ok, binary}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        prefix = Application.get_env(:waffle, :storage_dir_prefix, "priv/waffle/public")
        path = Path.join([prefix, "uploads/images/#{id}", "original#{ext}"])
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
end
