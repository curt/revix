defmodule Revix.Uploaders.Image do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  import Revix.Uploaders.Validation

  @versions [:original, :large, :medium, :thumb]

  # Versions whose dimensions are written as S3 metadata here and read back by
  # Revix.Media; ImageVersion is the single list of dimension-tracked versions.
  @dimension_versions Revix.Ecto.ImageVersion.values()

  @thumb_size 300

  @doc "Edge length of the square `:thumb` version, for `<img>` width/height."
  def thumb_size, do: @thumb_size

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
    size = "#{@thumb_size}x#{@thumb_size}"

    {:convert,
     "-auto-orient -strip -thumbnail #{size}^ -gravity center -extent #{size} -format jpg", :jpg}
  end

  def filename(version, _) do
    version
  end

  def storage_dir(_version, {_file, image}) do
    "uploads/images/#{image.id}"
  end

  def s3_object_headers(version, {file, _scope}) do
    [content_type: MIME.from_path(file.file_name)]
    |> Keyword.merge(meta_dimensions(version, file))
  end

  defp meta_dimensions(version, file) when version in @dimension_versions do
    case File.read(file.path) do
      {:ok, binary} ->
        case ExImageInfo.info(binary) do
          {_mime, width, height, _variant} ->
            [meta: [{"width", to_string(width)}, {"height", to_string(height)}]]

          nil ->
            []
        end

      {:error, _} ->
        []
    end
  end

  defp meta_dimensions(_version, _file), do: []

  def public_url(image, version) do
    case url({image.file, image}, version) do
      "//" <> _ = u -> u
      "/" <> _ = path -> Revix.URLs.absolute_url(path)
      u -> u
    end
  end
end
