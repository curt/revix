defmodule Revix.Media.Image do
  use Revix.Schema
  use Waffle.Ecto.Schema
  import Ecto.Changeset

  schema "images" do
    field :file, Revix.Uploaders.Image.Type
    field :alt, :string
    field :caption, :string
    field :caption_html, :string
    field :content_type, :string
    field :original_filename, :string
    field :author_uri, :string

    has_many :entry_images, Revix.Media.EntryImage
    has_many :entries, through: [:entry_images, :entry]
    has_many :dimensions, Revix.Media.ImageDimension

    timestamps()
  end

  def update_changeset(image, attrs) do
    image
    |> cast(attrs, [:alt, :caption])
    |> maybe_convert_caption_to_html()
  end

  def changeset(image, attrs) do
    image
    |> cast(attrs, [:alt, :caption, :author_uri, :content_type, :original_filename])
    |> validate_required([:author_uri])
    |> cast_attachments(attrs, [:file])
    |> validate_required([:file])
    |> maybe_convert_caption_to_html()
  end

  defp maybe_convert_caption_to_html(changeset) do
    case get_change(changeset, :caption) do
      nil ->
        changeset

      caption ->
        case Earmark.as_html(caption, compact_output: true) do
          {:ok, html, _} -> put_change(changeset, :caption_html, html)
          {:error, _, _} -> add_error(changeset, :caption, "could not be converted to HTML")
        end
    end
  end
end
