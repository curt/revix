defmodule Revix.Uploaders.Avatar do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  import Revix.Uploaders.Validation

  @versions [:thumb]

  def validate({file, _}) do
    validate_image(
      file,
      ~w(.jpg .jpeg .gif .png),
      [:jpeg, :gif, :png]
    )
  end

  # Define a thumbnail transformation:
  def transform(:thumb, _) do
    {:convert, "-strip -thumbnail 64x64^ -gravity center -extent 64x64 -format png", :png}
  end

  # Override the persisted filenames:
  def filename(version, _) do
    version
  end

  # Override the storage directory:
  def storage_dir(_version, {_file, scope}) do
    "uploads/people/#{scope.id}/avatars"
  end

  # Provide a default URL if there hasn't been a file uploaded
  def default_url(_version, scope) do
    "/identicon/#{scope.id}"
  end

  # Specify custom headers for s3 objects
  # Available options are [:cache_control, :content_disposition,
  #    :content_encoding, :content_length, :content_type,
  #    :expect, :expires, :storage_class, :website_redirect_location]
  #
  def s3_object_headers(_version, {file, _scope}) do
    [content_type: MIME.from_path(file.file_name)]
  end
end
