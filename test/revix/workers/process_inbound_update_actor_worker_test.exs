defmodule Revix.Workers.ProcessInboundUpdateActorWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.ProcessInboundUpdateActorWorker
  alias Revix.People
  alias Revix.People.Person

  import Revix.PeopleFixtures
  import Revix.FederationFixtures

  @actor_uri "https://remote.example.com/users/alice"

  defp remote_person_attrs(uri) do
    %{
      uri: uri,
      public_key: "fake-key",
      username: "alice",
      display_name: "Alice"
    }
  end

  defp insert_remote_person(uri \\ @actor_uri) do
    {:ok, person} = People.upsert_remote_person(remote_person_attrs(uri))
    person
  end

  defp activity(object, actor_uri) do
    %{
      "type" => "Update",
      "id" => "#{actor_uri}/activities/upd1",
      "actor" => actor_uri,
      "object" => object
    }
  end

  defp perform(object, actor_uri \\ @actor_uri) do
    perform_job(ProcessInboundUpdateActorWorker, %{
      "activity" => activity(object, actor_uri),
      "person_id" => person_fixture().id
    })
  end

  describe "self-authored Update{Person}" do
    test "refreshes the cached remote person from the origin" do
      insert_remote_person()
      stub_actor(@actor_uri, %{"name" => "Alice Renamed"})

      assert :ok = perform(%{"type" => "Person", "id" => @actor_uri})

      person = Repo.get_by!(Person, uri: @actor_uri)
      assert person.display_name == "Alice Renamed"
    end

    test "returns :ok when object is a plain URI string matching the actor" do
      insert_remote_person()
      stub_actor(@actor_uri, %{"name" => "Alice Renamed"})

      assert :ok = perform(@actor_uri)

      person = Repo.get_by!(Person, uri: @actor_uri)
      assert person.display_name == "Alice Renamed"
    end
  end

  describe "actor/object mismatch" do
    test "returns :ok and does not refresh when actor != object id" do
      insert_remote_person()

      other_actor = "https://remote.example.com/users/mallory"

      assert :ok = perform(%{"type" => "Person", "id" => @actor_uri}, other_actor)

      person = Repo.get_by!(Person, uri: @actor_uri)
      assert person.display_name == "Alice"
    end
  end

  describe "local target" do
    test "returns :ok and does not mutate a local person" do
      local = person_fixture()

      assert :ok = perform(%{"type" => "Person", "id" => local.uri}, local.uri)

      person = Repo.get_by!(Person, uri: local.uri)
      assert person.origin == :local
    end
  end

  describe "invalid activity" do
    test "returns error when object URI cannot be extracted" do
      assert {:error, :invalid_activity} = perform(nil)
    end

    test "returns error when actor is nil" do
      assert {:error, :invalid_activity} =
               perform_job(ProcessInboundUpdateActorWorker, %{
                 "activity" => %{
                   "type" => "Update",
                   "id" => "https://remote.example.com/activities/x",
                   "actor" => nil,
                   "object" => %{"type" => "Person", "id" => @actor_uri}
                 },
                 "person_id" => person_fixture().id
               })
    end
  end

  describe "origin mismatch" do
    test "returns :ok when the fetched actor document reports a different origin" do
      insert_remote_person()

      Req.Test.stub(:federation, fn conn ->
        Req.Test.json(
          conn,
          remote_actor_map(@actor_uri) |> Map.put("id", "https://evil.example.com/users/alice")
        )
      end)

      assert :ok = perform(%{"type" => "Person", "id" => @actor_uri})
    end
  end

  describe "federation fetch failure" do
    test "propagates the error when fetch_actor fails" do
      insert_remote_person()

      Req.Test.stub(:federation, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, _reason} = perform(%{"type" => "Person", "id" => @actor_uri})
    end
  end
end
