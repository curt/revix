defmodule Revix.Uploaders.Image do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  import Revix.Uploaders.Validation

  @versions [:original, :large, :medium, :thumb]

  def validate({file, _}) do
    validate_image(
      file,
      ~w(.jpg .jpeg .gif .png .webp),
      [:jpeg, :gif, :png, :webp]
    )
  end

  def transform(:original, _), do: :noaction

  def transform(:large, _) do
    {:convert, "-auto-orient -strip -resize 1200x1200> -quality 85 -format jpg", :jpg}
  end

  def transform(:medium, _) do
    {:convert, "-auto-orient -strip -resize 800x800> -quality 85 -format jpg", :jpg}
  end

  def transform(:thumb, _) do
    {:convert,
     "-auto-orient -strip -thumbnail 300x300^ -gravity center -extent 300x300 -format jpg", :jpg}
  end

  def acl(:original, _), do: :private
  def acl(_, _), do: :public_read

  def filename(version, _) do
    version
  end

  def storage_dir(_version, {_file, image}) do
    "uploads/images/#{image.id}"
  end

  def s3_object_headers(_version, {file, _scope}) do
    [content_type: MIME.from_path(file.file_name)]
  end
end
