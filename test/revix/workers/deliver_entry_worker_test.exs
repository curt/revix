defmodule Revix.Workers.DeliverEntryWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.DeliverEntryWorker
  alias Revix.Follows.Follow

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures
  import Revix.FederationFixtures
  import Revix.MediaFixtures
  alias Revix.Entries

  setup do
    stub_remote_server()
    :ok
  end

  defp insert_accepted_follow(follower_uri, following_uri) do
    id = Revix.Ecto.Base58Id.autogenerate()

    %Follow{id: id}
    |> Follow.create_changeset(%{
      uri: "tag:revix,2026-05-14:follow:#{id}",
      follower_uri: follower_uri,
      following_uri: following_uri,
      origin: :remote,
      accepted_at: DateTime.utc_now(:second)
    })
    |> Repo.insert!()
  end

  defp perform(entry_id, activity_type) do
    perform_job(DeliverEntryWorker, %{
      "entry_id" => entry_id,
      "activity_type" => activity_type
    })
  end

  defp create_comment(scope, parent, attrs) do
    uri_fn = fn id -> "https://example.com/notes/#{id}" end
    {:ok, comment} = Entries.create_comment(scope, parent, attrs, uri_fn, uri_fn)
    comment
  end

  describe "perform/1" do
    test "delivers Create activity to each accepted follower" do
      person = person_fixture()
      person = %{person | private_key: private_key_pem()}

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(Revix.People.Person, person.id),
          private_key: private_key_pem()
        )
      )

      checkin = checkin_fixture(%{author_uri: person.uri})
      insert_accepted_follow(remote_actor_uri(), person.uri)

      assert :ok = perform(checkin.id, "Create")
    end

    test "delivers Update activity to each accepted follower" do
      person = person_fixture()

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(Revix.People.Person, person.id),
          private_key: private_key_pem()
        )
      )

      checkin = checkin_fixture(%{author_uri: person.uri})
      insert_accepted_follow(remote_actor_uri(), person.uri)

      assert :ok = perform(checkin.id, "Update")
    end

    test "delivers Delete activity with plain URI as object" do
      delivered = Agent.start_link(fn -> nil end) |> elem(1)

      Req.Test.stub(:federation, fn conn ->
        case conn.method do
          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            Agent.update(delivered, fn _ -> Jason.decode!(body) end)

            conn
            |> Plug.Conn.put_resp_header("content-type", "text/plain")
            |> Plug.Conn.send_resp(202, "")

          "GET" ->
            Req.Test.json(conn, remote_actor_map())
        end
      end)

      person = person_fixture()

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(Revix.People.Person, person.id),
          private_key: private_key_pem()
        )
      )

      checkin = checkin_fixture(%{author_uri: person.uri})
      insert_accepted_follow(remote_actor_uri(), person.uri)

      assert :ok = perform(checkin.id, "Delete")

      activity = Agent.get(delivered, & &1)
      assert activity["type"] == "Delete"
      assert activity["object"] == checkin.uri
    end

    test "returns :ok with no delivery when person has no followers" do
      person = person_fixture()
      checkin = checkin_fixture(%{author_uri: person.uri})

      assert :ok = perform(checkin.id, "Create")
    end

    test "returns :ok when inbox delivery fails for a follower" do
      Req.Test.stub(:federation, fn conn ->
        case conn.method do
          "POST" -> Req.Test.transport_error(conn, :timeout)
          "GET" -> Req.Test.json(conn, remote_actor_map())
        end
      end)

      person = person_fixture()

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(Revix.People.Person, person.id),
          private_key: private_key_pem()
        )
      )

      checkin = checkin_fixture(%{author_uri: person.uri})
      insert_accepted_follow(remote_actor_uri(), person.uri)

      assert :ok = perform(checkin.id, "Create")
    end

    test "builds Create activity with correct fields" do
      delivered = Agent.start_link(fn -> nil end) |> elem(1)

      Req.Test.stub(:federation, fn conn ->
        case conn.method do
          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            Agent.update(delivered, fn _ -> Jason.decode!(body) end)

            conn
            |> Plug.Conn.put_resp_header("content-type", "text/plain")
            |> Plug.Conn.send_resp(202, "")

          "GET" ->
            Req.Test.json(conn, remote_actor_map())
        end
      end)

      person = person_fixture()

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(Revix.People.Person, person.id),
          private_key: private_key_pem()
        )
      )

      checkin = checkin_fixture(%{author_uri: person.uri})
      insert_accepted_follow(remote_actor_uri(), person.uri)

      assert :ok = perform(checkin.id, "Create")

      activity = Agent.get(delivered, & &1)
      assert activity["type"] == "Create"
      assert activity["actor"] == person.uri
      assert activity["to"] == ["https://www.w3.org/ns/activitystreams#Public"]
      assert activity["cc"] == [RevixWeb.CanonicalRoutes.person_followers_url(person.id)]
      assert activity["object"]["type"] == "Note"
      assert activity["object"]["id"] == checkin.uri
      assert activity["object"]["attributedTo"] == person.uri
    end

    test "includes attachments in Create object when entry has images" do
      delivered = Agent.start_link(fn -> nil end) |> elem(1)

      Req.Test.stub(:federation, fn conn ->
        case conn.method do
          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            Agent.update(delivered, fn _ -> Jason.decode!(body) end)

            conn
            |> Plug.Conn.put_resp_header("content-type", "text/plain")
            |> Plug.Conn.send_resp(202, "")

          "GET" ->
            Req.Test.json(conn, remote_actor_map())
        end
      end)

      person = person_fixture()

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(Revix.People.Person, person.id),
          private_key: private_key_pem()
        )
      )

      checkin = checkin_fixture(%{author_uri: person.uri})
      image = image_fixture(%{author_uri: person.uri})
      entry_image_fixture(%{entry_id: checkin.id, image_id: image.id, position: 0})
      insert_accepted_follow(remote_actor_uri(), person.uri)

      assert :ok = perform(checkin.id, "Create")

      activity = Agent.get(delivered, & &1)
      assert [attachment] = activity["object"]["attachment"]
      assert attachment["type"] == "Document"
      assert attachment["mediaType"] == image.content_type
      assert is_binary(attachment["url"])
    end

    test "builds Create activity for post entries" do
      delivered = Agent.start_link(fn -> nil end) |> elem(1)

      Req.Test.stub(:federation, fn conn ->
        case conn.method do
          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            Agent.update(delivered, fn _ -> Jason.decode!(body) end)

            conn
            |> Plug.Conn.put_resp_header("content-type", "text/plain")
            |> Plug.Conn.send_resp(202, "")

          "GET" ->
            Req.Test.json(conn, remote_actor_map())
        end
      end)

      person = person_fixture()

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(Revix.People.Person, person.id),
          private_key: private_key_pem()
        )
      )

      post = post_fixture(%{author_uri: person.uri, name: "Worker Post"})
      insert_accepted_follow(remote_actor_uri(), person.uri)

      assert :ok = perform(post.id, "Create")

      activity = Agent.get(delivered, & &1)
      assert activity["object"]["type"] == "Note"
      assert activity["object"]["id"] == post.uri
      assert activity["object"]["name"] == "Worker Post"
      assert activity["cc"] == [RevixWeb.CanonicalRoutes.person_followers_url(person.id)]
    end

    test "builds Create activity for note entries" do
      delivered = Agent.start_link(fn -> nil end) |> elem(1)

      Req.Test.stub(:federation, fn conn ->
        case conn.method do
          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            Agent.update(delivered, fn _ -> Jason.decode!(body) end)

            conn
            |> Plug.Conn.put_resp_header("content-type", "text/plain")
            |> Plug.Conn.send_resp(202, "")

          "GET" ->
            Req.Test.json(conn, remote_actor_map())
        end
      end)

      person = person_fixture()
      scope = Revix.People.Scope.for_person(person)

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(Revix.People.Person, person.id),
          private_key: private_key_pem()
        )
      )

      checkin = checkin_fixture(%{author_uri: person.uri})

      comment =
        create_comment(scope, checkin, %{"content" => "Worker note", "published_tz" => "UTC"})

      insert_accepted_follow(remote_actor_uri(), person.uri)

      assert :ok = perform(comment.id, "Create")

      activity = Agent.get(delivered, & &1)
      assert activity["object"]["type"] == "Note"
      assert activity["object"]["id"] == comment.uri
      assert activity["object"]["inReplyTo"] == checkin.uri
    end

    test "builds Update activity with published and timestamp-suffixed id" do
      delivered = Agent.start_link(fn -> nil end) |> elem(1)

      Req.Test.stub(:federation, fn conn ->
        case conn.method do
          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            Agent.update(delivered, fn _ -> Jason.decode!(body) end)

            conn
            |> Plug.Conn.put_resp_header("content-type", "text/plain")
            |> Plug.Conn.send_resp(202, "")

          "GET" ->
            Req.Test.json(conn, remote_actor_map())
        end
      end)

      person = person_fixture()

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(Revix.People.Person, person.id),
          private_key: private_key_pem()
        )
      )

      checkin = checkin_fixture(%{author_uri: person.uri})
      {:ok, updated_checkin} = Entries.update_local_checkin(checkin, %{"content" => "Edited"})
      insert_accepted_follow(remote_actor_uri(), person.uri)

      assert :ok = perform(updated_checkin.id, "Update")

      activity = Agent.get(delivered, & &1)
      assert activity["type"] == "Update"
      assert String.starts_with?(activity["id"], updated_checkin.uri <> "#update-")
      assert is_binary(activity["published"])
      assert activity["object"]["type"] == "Note"
    end

    test "Create activity includes published matching published_at_utc" do
      delivered = Agent.start_link(fn -> nil end) |> elem(1)

      Req.Test.stub(:federation, fn conn ->
        case conn.method do
          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            Agent.update(delivered, fn _ -> Jason.decode!(body) end)

            conn
            |> Plug.Conn.put_resp_header("content-type", "text/plain")
            |> Plug.Conn.send_resp(202, "")

          "GET" ->
            Req.Test.json(conn, remote_actor_map())
        end
      end)

      person = person_fixture()

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(Revix.People.Person, person.id),
          private_key: private_key_pem()
        )
      )

      checkin = checkin_fixture(%{author_uri: person.uri})
      insert_accepted_follow(remote_actor_uri(), person.uri)

      assert :ok = perform(checkin.id, "Create")

      activity = Agent.get(delivered, & &1)
      assert activity["type"] == "Create"
      assert activity["published"] == DateTime.to_iso8601(checkin.published_at_utc)
      assert activity["id"] == checkin.uri <> "#create"
    end
  end
end
