defmodule Revix.Media.EntryImageTest do
  use Revix.DataCase

  alias Revix.Media.EntryImage

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      changeset =
        EntryImage.changeset(%EntryImage{}, %{
          entry_id: Revix.Ecto.Base58Id.autogenerate(),
          image_id: Revix.Ecto.Base58Id.autogenerate(),
          position: 0
        })

      assert changeset.valid?
    end

    test "requires entry_id" do
      changeset =
        EntryImage.changeset(%EntryImage{}, %{
          image_id: Revix.Ecto.Base58Id.autogenerate(),
          position: 0
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).entry_id
    end

    test "requires image_id" do
      changeset =
        EntryImage.changeset(%EntryImage{}, %{
          entry_id: Revix.Ecto.Base58Id.autogenerate(),
          position: 0
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).image_id
    end

    test "defaults position to 0 when not provided" do
      changeset =
        EntryImage.changeset(%EntryImage{}, %{
          entry_id: Revix.Ecto.Base58Id.autogenerate(),
          image_id: Revix.Ecto.Base58Id.autogenerate()
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :position) == 0
    end

    test "validates position is not negative" do
      changeset =
        EntryImage.changeset(%EntryImage{}, %{
          entry_id: Revix.Ecto.Base58Id.autogenerate(),
          image_id: Revix.Ecto.Base58Id.autogenerate(),
          position: -1
        })

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).position
    end
  end
end
