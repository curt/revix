defmodule Revix.Media.EntryImage do
  use Revix.Schema
  import Ecto.Changeset

  schema "entry_images" do
    belongs_to :entry, Revix.Entries.Entry
    belongs_to :image, Revix.Media.Image
    field :position, :integer, default: 0

    timestamps()
  end

  def changeset(entry_image, attrs) do
    entry_image
    |> cast(attrs, [:entry_id, :image_id, :position])
    |> validate_required([:entry_id, :image_id])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint([:entry_id, :image_id])
    |> foreign_key_constraint(:entry_id)
    |> foreign_key_constraint(:image_id)
  end
end
