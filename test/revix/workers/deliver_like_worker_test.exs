defmodule Revix.Workers.DeliverLikeWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.DeliverLikeWorker
  alias Revix.Likes.Like
  alias Revix.People.Person

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures
  import Revix.FederationFixtures

  @remote_object_uri "https://remote.example.com/entries/abc"

  defp insert_like(author_uri, object_uri) do
    id = Revix.Ecto.Base58Id.autogenerate()

    %Like{id: id}
    |> Like.create_changeset(%{
      like_uri: "https://example.com/likes/#{id}",
      author_uri: author_uri,
      object_uri: object_uri,
      origin: :local,
      published_at_utc: DateTime.utc_now(:second),
      published_at_local: NaiveDateTime.utc_now(:second),
      published_tz: "UTC"
    })
    |> Repo.insert!()
  end

  defp set_private_key(person) do
    Repo.update!(
      Ecto.Changeset.change(Repo.get!(Person, person.id), private_key: private_key_pem())
    )
  end

  defp stub_with_remote_object do
    Req.Test.stub(:federation, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/entries/abc"} ->
          Req.Test.json(conn, %{
            "id" => @remote_object_uri,
            "type" => "Note",
            "attributedTo" => remote_actor_uri()
          })

        {"GET", "/users/alice"} ->
          Req.Test.json(conn, remote_actor_map())

        {"POST", "/users/alice/inbox"} ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "text/plain")
          |> Plug.Conn.send_resp(202, "")
      end
    end)
  end

  describe "perform/1 with remote object" do
    test "delivers Like activity to object author's inbox and returns :ok" do
      stub_with_remote_object()

      person = person_fixture()
      set_private_key(person)
      like = insert_like(person.uri, @remote_object_uri)

      assert :ok = perform_job(DeliverLikeWorker, %{"like_id" => like.id})
    end

    test "builds a Like activity with correct fields" do
      delivered = Agent.start_link(fn -> nil end) |> elem(1)

      Req.Test.stub(:federation, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/entries/abc"} ->
            Req.Test.json(conn, %{
              "id" => @remote_object_uri,
              "type" => "Note",
              "attributedTo" => remote_actor_uri()
            })

          {"GET", "/users/alice"} ->
            Req.Test.json(conn, remote_actor_map())

          {"POST", "/users/alice/inbox"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            Agent.update(delivered, fn _ -> Jason.decode!(body) end)

            conn
            |> Plug.Conn.put_resp_header("content-type", "text/plain")
            |> Plug.Conn.send_resp(202, "")
        end
      end)

      person = person_fixture()
      set_private_key(person)
      like = insert_like(person.uri, @remote_object_uri)

      :ok = perform_job(DeliverLikeWorker, %{"like_id" => like.id})

      activity = Agent.get(delivered, & &1)
      assert activity["type"] == "Like"
      assert activity["id"] == like.like_uri
      assert activity["actor"] == like.author_uri
      assert activity["object"] == like.object_uri
    end

    test "returns {:error, reason} on delivery failure" do
      Req.Test.stub(:federation, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/entries/abc"} ->
            Req.Test.json(conn, %{
              "id" => @remote_object_uri,
              "type" => "Note",
              "attributedTo" => remote_actor_uri()
            })

          {"GET", "/users/alice"} ->
            Req.Test.json(conn, remote_actor_map())

          {"POST", _} ->
            Req.Test.transport_error(conn, :timeout)
        end
      end)

      person = person_fixture()
      set_private_key(person)
      like = insert_like(person.uri, @remote_object_uri)

      assert {:error, _reason} = perform_job(DeliverLikeWorker, %{"like_id" => like.id})
    end
  end

  describe "perform/1 with local object" do
    test "returns :ok without making any HTTP requests" do
      Req.Test.stub(:federation, fn conn ->
        flunk("Unexpected HTTP call: #{conn.method} #{conn.request_path}")
      end)

      liker = person_fixture()
      set_private_key(liker)
      checkin = checkin_fixture()
      like = insert_like(liker.uri, checkin.uri)

      assert :ok = perform_job(DeliverLikeWorker, %{"like_id" => like.id})
    end
  end
end
