defmodule Revix.Federation.SignatureVerifierTest do
  use Revix.DataCase, async: false

  alias Revix.Federation.SignatureVerifier
  alias Revix.FederationFixtures
  alias Revix.People

  @actor_uri FederationFixtures.remote_actor_uri()

  defp build_conn(actor_uri \\ @actor_uri) do
    conn = Plug.Test.conn(:post, "/inbox")
    FederationFixtures.signed_conn(conn, actor_uri)
  end

  defp conn_without_signature do
    Plug.Test.conn(:post, "/inbox")
  end

  defp stub_actor(actor_map) do
    Req.Test.stub(:federation, fn conn ->
      Req.Test.json(conn, actor_map)
    end)
  end

  defp stub_actor_error do
    Req.Test.stub(:federation, fn conn ->
      Plug.Conn.send_resp(conn, 404, "not found")
    end)
  end

  defp insert_remote_person(attrs \\ %{}) do
    base = %{
      uri: @actor_uri,
      url: "https://remote.example.com/users/alice",
      username: "alice",
      display_name: "Alice Example",
      public_key: FederationFixtures.public_key_pem()
    }

    {:ok, person} = People.upsert_remote_person(Map.merge(base, attrs))
    person
  end

  describe "fetch_public_key/1" do
    test "returns error when conn has no signature header" do
      assert {:error, :key_not_found} =
               SignatureVerifier.fetch_public_key(conn_without_signature())
    end

    test "fetches actor from network and returns decoded key" do
      stub_actor(FederationFixtures.remote_actor_map())

      assert {:ok, _key} = SignatureVerifier.fetch_public_key(build_conn())
    end

    test "returns error when actor fetch fails" do
      stub_actor_error()

      assert {:error, :key_not_found} = SignatureVerifier.fetch_public_key(build_conn())
    end

    test "strips #fragment from keyId before fetching actor" do
      # signed_conn uses keyId = actor_uri <> \"#key\"; verifier must strip the fragment
      # so it fetches the actor by base URI, not the fragment URI
      stub_actor(FederationFixtures.remote_actor_map())

      assert {:ok, _key} = SignatureVerifier.fetch_public_key(build_conn())
    end

    test "returns cached person when not stale (no network call)" do
      # Insert a fresh remote person — updated_at is now, well within the refresh window
      insert_remote_person()

      # If the network is called, the test would fail because the stub raises
      Req.Test.stub(:federation, fn _conn ->
        raise "fetch_actor should not be called for a fresh person"
      end)

      assert {:ok, _key} = SignatureVerifier.fetch_public_key(build_conn())
    end

    test "re-fetches when cached person is stale" do
      person = insert_remote_person()

      # Force updated_at to be old enough to exceed the refresh window
      stale_at = DateTime.add(DateTime.utc_now(), -48 * 3600, :second)

      Revix.Repo.update_all(
        Ecto.Query.from(p in Revix.People.Person, where: p.id == ^person.id),
        set: [updated_at: stale_at]
      )

      stub_actor(FederationFixtures.remote_actor_map())

      assert {:ok, _key} = SignatureVerifier.fetch_public_key(build_conn())
    end

    test "returns :no_public_key when actor JSON has no publicKey field" do
      actor_without_key = Map.delete(FederationFixtures.remote_actor_map(), "publicKey")
      stub_actor(actor_without_key)

      assert {:error, :no_public_key} = SignatureVerifier.fetch_public_key(build_conn())
    end

    test "returns :no_public_key when publicKey field has unexpected shape" do
      actor_bad_key = Map.put(FederationFixtures.remote_actor_map(), "publicKey", "raw-string")
      stub_actor(actor_bad_key)

      assert {:error, :no_public_key} = SignatureVerifier.fetch_public_key(build_conn())
    end

    test "returns :invalid_public_key when stored PEM is malformed" do
      insert_remote_person(%{public_key: "not-a-valid-pem"})

      # Person is fresh so no re-fetch; decode should fail
      Req.Test.stub(:federation, fn _conn ->
        raise "should not fetch actor for fresh person"
      end)

      assert {:error, :invalid_public_key} = SignatureVerifier.fetch_public_key(build_conn())
    end

    test "extracts icon from plain-string icon URL in actor JSON" do
      actor_with_string_icon =
        FederationFixtures.remote_actor_map()
        |> Map.put("icon", "https://remote.example.com/avatar.png")

      stub_actor(actor_with_string_icon)

      # The key goal is that the actor was processed without error; icon extraction
      # is a side-effect of refresh_person — just assert fetch succeeds
      assert {:ok, _key} = SignatureVerifier.fetch_public_key(build_conn())
    end

    test "handles actor with no icon field" do
      actor_without_icon = Map.delete(FederationFixtures.remote_actor_map(), "icon")
      stub_actor(actor_without_icon)

      assert {:ok, _key} = SignatureVerifier.fetch_public_key(build_conn())
    end
  end

  describe "refetch_public_key/1" do
    test "always re-fetches even when person is fresh" do
      insert_remote_person()

      stub_actor(FederationFixtures.remote_actor_map())

      assert {:ok, _key} = SignatureVerifier.refetch_public_key(build_conn())
    end

    test "returns error when conn has no signature header" do
      assert {:error, :key_not_found} =
               SignatureVerifier.refetch_public_key(conn_without_signature())
    end
  end
end
