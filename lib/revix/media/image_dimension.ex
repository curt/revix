defmodule Revix.Media.ImageDimension do
  use Revix.Schema
  import Ecto.Changeset

  schema "image_dimensions" do
    belongs_to :image, Revix.Media.Image
    field :version, Revix.Ecto.ImageVersion
    field :width, :integer
    field :height, :integer

    timestamps()
  end

  def changeset(image_dimension, attrs) do
    image_dimension
    |> cast(attrs, [:image_id, :version, :width, :height])
    |> validate_required([:image_id, :version, :width, :height])
    |> validate_number(:width, greater_than: 0)
    |> validate_number(:height, greater_than: 0)
    |> unique_constraint([:image_id, :version])
    |> foreign_key_constraint(:image_id)
  end
end
