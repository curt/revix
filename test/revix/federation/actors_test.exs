defmodule Revix.Federation.ActorsTest do
  use Revix.DataCase, async: false

  alias Revix.Federation.Actors

  @jpeg File.read!("test/support/fixtures/test.jpg")

  describe "get_or_fetch_person_by_uri/2" do
    test "stores an actor whose document has no id under the URI it was fetched from" do
      uri = "https://remote.example.com/users/no-id"

      Req.Test.stub(:federation, fn conn ->
        Req.Test.json(conn, %{
          "type" => "Person",
          "preferredUsername" => "noid",
          "name" => "No Id",
          "publicKey" => %{"publicKeyPem" => "fake-key"}
        })
      end)

      assert {:ok, person} = Actors.get_or_fetch_person_by_uri(uri)
      assert person.uri == uri
      assert person.username == "noid"
    end
  end

  describe "upsert_remote_person/1" do
    test "downloads and stores the actor's avatar" do
      Req.Test.stub(:federation, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.send_resp(200, @jpeg)
      end)

      assert {:ok, person} =
               Actors.upsert_remote_person(%{
                 uri: "https://remote.example.com/users/erin",
                 public_key: "fake-key",
                 username: "erin",
                 display_name: "Erin",
                 icon_url: "https://remote.example.com/users/erin/avatar.jpg"
               })

      assert %{avatar: %{file_name: "avatar.jpg"}} = Revix.Repo.reload!(person)
    end
  end
end
