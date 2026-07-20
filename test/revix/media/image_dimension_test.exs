defmodule Revix.Media.ImageDimensionTest do
  use Revix.DataCase

  alias Revix.Media.ImageDimension

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      changeset =
        ImageDimension.changeset(%ImageDimension{}, %{
          image_id: Revix.Ecto.Base58Id.autogenerate(),
          version: :large,
          width: 1200,
          height: 600
        })

      assert changeset.valid?
    end

    test "requires image_id" do
      changeset =
        ImageDimension.changeset(%ImageDimension{}, %{
          version: :large,
          width: 1200,
          height: 600
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).image_id
    end

    test "requires version" do
      changeset =
        ImageDimension.changeset(%ImageDimension{}, %{
          image_id: Revix.Ecto.Base58Id.autogenerate(),
          width: 1200,
          height: 600
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).version
    end

    test "requires width" do
      changeset =
        ImageDimension.changeset(%ImageDimension{}, %{
          image_id: Revix.Ecto.Base58Id.autogenerate(),
          version: :large,
          height: 600
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).width
    end

    test "requires height" do
      changeset =
        ImageDimension.changeset(%ImageDimension{}, %{
          image_id: Revix.Ecto.Base58Id.autogenerate(),
          version: :large,
          width: 1200
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).height
    end

    test "validates width is positive" do
      changeset =
        ImageDimension.changeset(%ImageDimension{}, %{
          image_id: Revix.Ecto.Base58Id.autogenerate(),
          version: :large,
          width: 0,
          height: 600
        })

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).width
    end

    test "validates height is positive" do
      changeset =
        ImageDimension.changeset(%ImageDimension{}, %{
          image_id: Revix.Ecto.Base58Id.autogenerate(),
          version: :large,
          width: 1200,
          height: 0
        })

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).height
    end

    test "rejects an invalid version" do
      changeset =
        ImageDimension.changeset(%ImageDimension{}, %{
          image_id: Revix.Ecto.Base58Id.autogenerate(),
          version: :thumb,
          width: 300,
          height: 300
        })

      refute changeset.valid?
    end

    test "enforces a unique image_id/version pair" do
      image = Revix.MediaFixtures.image_fixture()
      id = Revix.Ecto.Base58Id.autogenerate()

      attrs = %{image_id: image.id, version: :large, width: 1200, height: 600}

      {:ok, _} =
        %ImageDimension{id: id}
        |> ImageDimension.changeset(attrs)
        |> Revix.Repo.insert()

      {:error, changeset} =
        %ImageDimension{id: Revix.Ecto.Base58Id.autogenerate()}
        |> ImageDimension.changeset(attrs)
        |> Revix.Repo.insert()

      refute changeset.valid?
      assert "has already been taken" in errors_on(changeset).image_id
    end
  end
end
