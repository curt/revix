defmodule Revix.Sites.Site do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:endpoint, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime]

  schema "sites" do
    field :title, :string
    field :description, :string

    timestamps()
  end

  def changeset(site, attrs) do
    site
    |> cast(attrs, [:endpoint, :title, :description])
    |> validate_required([:endpoint])
    |> validate_length(:title, max: 255)
  end
end
