defmodule Revix.PlacesMergeTest do
  use Revix.DataCase, async: true

  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

  alias Revix.Places
  alias Revix.Places.Place
  alias Revix.EntryPlaces
  alias Revix.Repo

  # ── merge_into/2 ────────────────────────────────────────────────────────────

  describe "merge_into/2 — validation" do
    test "returns error when source_ids is empty" do
      target = place_fixture()
      assert {:error, :invalid_sources} = Places.merge_into(target, [])
    end

    test "returns error when source_ids contains the target's own ID" do
      target = place_fixture()
      other = place_fixture()
      assert {:error, :invalid_sources} = Places.merge_into(target, [target.id, other.id])
    end

    test "returns error when a source ID does not exist" do
      target = place_fixture()
      assert {:error, :invalid_sources} = Places.merge_into(target, ["nonexistentid11"])
    end

    test "returns error when a source ID references a remote place" do
      target = place_fixture()

      {:ok, remote} =
        %Place{}
        |> Ecto.Changeset.change(%{
          id: Revix.Ecto.Base58Id.autogenerate(),
          uri: "https://remote.example.com/places/1",
          url: "https://remote.example.com/places/1",
          name: "Remote Place",
          origin: :remote,
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })
        |> Repo.insert()

      assert {:error, :invalid_sources} = Places.merge_into(target, [remote.id])
    end
  end

  describe "merge_into/2 — checkins" do
    test "reassigns checkins from source to target" do
      target = place_fixture()
      source = place_fixture()

      checkin1 = checkin_fixture(%{place_uri: source.uri})
      checkin2 = checkin_fixture(%{place_uri: source.uri})

      assert {:ok, _} = Places.merge_into(target, [source.id])

      updated1 = Repo.get(Revix.Entries.Entry, checkin1.id)
      updated2 = Repo.get(Revix.Entries.Entry, checkin2.id)
      assert updated1.place_uri == target.uri
      assert updated2.place_uri == target.uri
    end

    test "does not touch checkins for unrelated places" do
      target = place_fixture()
      source = place_fixture()
      other = place_fixture()

      bystander = checkin_fixture(%{place_uri: other.uri})

      assert {:ok, _} = Places.merge_into(target, [source.id])

      unchanged = Repo.get(Revix.Entries.Entry, bystander.id)
      assert unchanged.place_uri == other.uri
    end

    test "returns checkin count in result tuple" do
      target = place_fixture()
      source = place_fixture()

      checkin_fixture(%{place_uri: source.uri})
      checkin_fixture(%{place_uri: source.uri})

      assert {:ok, {2, _post_place_count}} = Places.merge_into(target, [source.id])
    end

    test "merges checkins from multiple sources" do
      target = place_fixture()
      source1 = place_fixture()
      source2 = place_fixture()

      checkin_fixture(%{place_uri: source1.uri})
      checkin_fixture(%{place_uri: source2.uri})

      assert {:ok, {2, _}} = Places.merge_into(target, [source1.id, source2.id])

      assert Repo.aggregate(
               Ecto.Query.from(e in Revix.Entries.Entry,
                 where: e.place_uri == ^target.uri and e.type == :checkin
               ),
               :count
             ) == 2
    end
  end

  describe "merge_into/2 — entry_places (post associations)" do
    test "reassigns entry_places rows from source to target" do
      target = place_fixture()
      source = place_fixture()
      post = post_fixture()

      {:ok, _} = EntryPlaces.add_place(post.uri, source.uri)

      assert {:ok, _} = Places.merge_into(target, [source.id])

      assert EntryPlaces.place_of?(target.uri, post.uri)
      refute EntryPlaces.place_of?(source.uri, post.uri)
    end

    test "does not duplicate entry_places when post already linked to target" do
      target = place_fixture()
      source = place_fixture()
      post = post_fixture()

      {:ok, _} = EntryPlaces.add_place(post.uri, target.uri)
      {:ok, _} = EntryPlaces.add_place(post.uri, source.uri)

      assert {:ok, _} = Places.merge_into(target, [source.id])

      count =
        Repo.aggregate(
          Ecto.Query.from(ep in Revix.EntryPlaces.EntryPlace,
            where: ep.entry_uri == ^post.uri and ep.place_uri == ^target.uri
          ),
          :count
        )

      assert count == 1
      refute EntryPlaces.place_of?(source.uri, post.uri)
    end

    test "returns inserted entry_place count in result tuple" do
      target = place_fixture()
      source = place_fixture()
      post1 = post_fixture()
      post2 = post_fixture()

      {:ok, _} = EntryPlaces.add_place(post1.uri, source.uri)
      {:ok, _} = EntryPlaces.add_place(post2.uri, source.uri)

      assert {:ok, {_checkins, 2}} = Places.merge_into(target, [source.id])
    end

    test "does not touch entry_places for unrelated places" do
      target = place_fixture()
      source = place_fixture()
      other = place_fixture()
      post = post_fixture()

      {:ok, _} = EntryPlaces.add_place(post.uri, other.uri)

      assert {:ok, _} = Places.merge_into(target, [source.id])

      assert EntryPlaces.place_of?(other.uri, post.uri)
    end

    test "merges entry_places from multiple sources without duplicates" do
      target = place_fixture()
      source1 = place_fixture()
      source2 = place_fixture()
      post = post_fixture()

      {:ok, _} = EntryPlaces.add_place(post.uri, source1.uri)
      {:ok, _} = EntryPlaces.add_place(post.uri, source2.uri)

      assert {:ok, _} = Places.merge_into(target, [source1.id, source2.id])

      assert EntryPlaces.place_of?(target.uri, post.uri)

      count =
        Repo.aggregate(
          Ecto.Query.from(ep in Revix.EntryPlaces.EntryPlace,
            where: ep.entry_uri == ^post.uri and ep.place_uri == ^target.uri
          ),
          :count
        )

      assert count == 1
    end
  end

  describe "merge_into/2 — source deletion" do
    test "deletes source places after merge" do
      target = place_fixture()
      source = place_fixture()

      assert {:ok, _} = Places.merge_into(target, [source.id])

      assert {:error, :not_found} = Places.get_local_place(source.id)
    end

    test "deletes multiple source places" do
      target = place_fixture()
      source1 = place_fixture()
      source2 = place_fixture()

      assert {:ok, _} = Places.merge_into(target, [source1.id, source2.id])

      assert {:error, :not_found} = Places.get_local_place(source1.id)
      assert {:error, :not_found} = Places.get_local_place(source2.id)
    end

    test "does not delete the target place" do
      target = place_fixture()
      source = place_fixture()

      assert {:ok, _} = Places.merge_into(target, [source.id])

      assert {:ok, _} = Places.get_local_place(target.id)
    end

    test "works when source has no checkins or posts" do
      target = place_fixture()
      source = place_fixture()

      assert {:ok, {0, 0}} = Places.merge_into(target, [source.id])

      assert {:error, :not_found} = Places.get_local_place(source.id)
    end
  end

  describe "merge_into/2 — atomicity" do
    test "does not partially apply on invalid_sources before transaction" do
      target = place_fixture()
      source = place_fixture()
      checkin_fixture(%{place_uri: source.uri})

      # One valid + one invalid → should fail before transaction
      assert {:error, :invalid_sources} =
               Places.merge_into(target, [source.id, "nonexistentid11"])

      # Source place still exists
      assert {:ok, _} = Places.get_local_place(source.id)

      # Checkin still points at source
      checkins =
        Repo.all(
          Ecto.Query.from(e in Revix.Entries.Entry,
            where: e.place_uri == ^source.uri
          )
        )

      assert length(checkins) == 1
    end
  end
end
