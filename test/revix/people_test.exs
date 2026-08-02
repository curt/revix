defmodule Revix.PeopleTest do
  use Revix.DataCase

  alias Revix.People

  import Revix.PeopleFixtures
  alias Revix.People.{Person, PersonToken}

  describe "get_person_by_email/1" do
    test "does not return the person if the email does not exist" do
      refute People.get_person_by_email("unknown@example.com")
    end

    test "returns the person if the email exists" do
      %{id: id} = person = person_fixture()
      assert %Person{id: ^id} = People.get_person_by_email(person.email)
    end
  end

  describe "get_person_by_email_and_password/2" do
    test "does not return the person if the email does not exist" do
      refute People.get_person_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the person if the password is not valid" do
      person = person_fixture() |> set_password()
      refute People.get_person_by_email_and_password(person.email, "invalid")
    end

    test "returns the person if the email and password are valid" do
      %{id: id} = person = person_fixture() |> set_password()

      assert %Person{id: ^id} =
               People.get_person_by_email_and_password(person.email, valid_person_password())
    end
  end

  describe "get_person!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        # out of bounds for random 64-bit value
        People.get_person!("zzzzzzzzzzz")
      end
    end

    test "returns the person with the given id" do
      %{id: id} = person = person_fixture()
      assert %Person{id: ^id} = People.get_person!(person.id)
    end
  end

  describe "get_person/1" do
    test "returns {:error, :not_found} if id does not exist" do
      assert People.get_person("zzzzzzzzzzz") == {:error, :not_found}
    end

    test "returns {:error, :not_found} if id is malformed" do
      assert People.get_person("not-valid-id") == {:error, :not_found}
    end

    test "returns {:ok, person} for a local person" do
      %{id: id} = person = person_fixture()
      assert {:ok, %Person{id: ^id}} = People.get_person(person.id)
    end
  end

  describe "register_person/3" do
    setup do
      uri_fn = fn id -> "http://localhost:4000/people/#{id}" end
      url_fn = fn id, _username -> "http://localhost:4000/people/#{id}" end
      %{uri_fn: uri_fn, url_fn: url_fn}
    end

    test "requires email to be set", %{uri_fn: uri_fn, url_fn: url_fn} do
      {:error, changeset} = People.register_person(%{}, uri_fn, url_fn)

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given", %{uri_fn: uri_fn, url_fn: url_fn} do
      {:error, changeset} = People.register_person(%{email: "not valid"}, uri_fn, url_fn)

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security", %{uri_fn: uri_fn, url_fn: url_fn} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = People.register_person(%{email: too_long}, uri_fn, url_fn)
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{uri_fn: uri_fn, url_fn: url_fn} do
      %{email: email} = person_fixture()
      {:error, changeset} = People.register_person(%{email: email}, uri_fn, url_fn)
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = People.register_person(%{email: String.upcase(email)}, uri_fn, url_fn)
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers people without password", %{uri_fn: uri_fn, url_fn: url_fn} do
      email = unique_person_email()

      {:ok, person} =
        People.register_person(valid_person_attributes(email: email), uri_fn, url_fn)

      assert person.email == email
      assert is_nil(person.hashed_password)
      assert is_nil(person.confirmed_at)
      assert is_nil(person.password)
    end

    test "encrypts the private key at rest", %{uri_fn: uri_fn, url_fn: url_fn} do
      {:ok, person} =
        People.register_person(valid_person_attributes(), uri_fn, url_fn)

      # The schema field decrypts transparently — value is a PEM string
      assert String.starts_with?(person.private_key, "-----BEGIN RSA PRIVATE KEY-----") or
               String.starts_with?(person.private_key, "-----BEGIN PRIVATE KEY-----")

      # The raw DB column is binary ciphertext, not PEM text
      %{rows: [[raw]]} =
        Revix.Repo.query!("SELECT private_key FROM people WHERE id = $1", [person.id])

      refute is_nil(raw)
      refute String.starts_with?(raw, "-----")
    end

    test "private key round-trips through the database", %{uri_fn: uri_fn, url_fn: url_fn} do
      {:ok, person} =
        People.register_person(valid_person_attributes(), uri_fn, url_fn)

      reloaded = People.get_person!(person.id)
      assert reloaded.private_key == person.private_key
    end

    test "decrypts private key to known plaintext", %{uri_fn: uri_fn, url_fn: url_fn} do
      # A minimal RSA private key in PEM format used as a known sentinel value.
      # X509 emits PKCS#8 ("BEGIN PRIVATE KEY") format for RSA keys.
      known_pem = X509.PrivateKey.new_rsa(512) |> X509.PrivateKey.to_pem()

      {:ok, person} =
        People.register_person(valid_person_attributes(), uri_fn, url_fn)

      person
      |> Ecto.Changeset.change(%{private_key: known_pem})
      |> Revix.Repo.update!()

      reloaded = People.get_person!(person.id)
      assert reloaded.private_key == known_pem
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert People.sudo_mode?(%Person{authenticated_at: DateTime.utc_now()})
      assert People.sudo_mode?(%Person{authenticated_at: DateTime.add(now, -19, :minute)})
      refute People.sudo_mode?(%Person{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute People.sudo_mode?(
               %Person{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute People.sudo_mode?(%Person{})
    end
  end

  describe "change_person_email/3" do
    test "returns a person changeset" do
      assert %Ecto.Changeset{} = changeset = People.change_person_email(%Person{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_person_update_email_instructions/3" do
    setup do
      %{person: person_fixture()}
    end

    test "sends token through notification", %{person: person} do
      token =
        extract_person_token(fn url ->
          People.deliver_person_update_email_instructions(person, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert person_token = Repo.get_by(PersonToken, token: :crypto.hash(:sha256, token))
      assert person_token.person_id == person.id
      assert person_token.sent_to == person.email
      assert person_token.context == "change:current@example.com"
    end
  end

  describe "update_person_email/2" do
    setup do
      person = unconfirmed_person_fixture()
      email = unique_person_email()

      token =
        extract_person_token(fn url ->
          People.deliver_person_update_email_instructions(
            %{person | email: email},
            person.email,
            url
          )
        end)

      %{person: person, token: token, email: email}
    end

    test "updates the email with a valid token", %{person: person, token: token, email: email} do
      assert {:ok, %{email: ^email}} = People.update_person_email(person, token)
      changed_person = Repo.get!(Person, person.id)
      assert changed_person.email != person.email
      assert changed_person.email == email
      refute Repo.get_by(PersonToken, person_id: person.id)
    end

    test "does not update email with invalid token", %{person: person} do
      assert People.update_person_email(person, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(Person, person.id).email == person.email
      assert Repo.get_by(PersonToken, person_id: person.id)
    end

    test "does not update email if person email changed", %{person: person, token: token} do
      assert People.update_person_email(%{person | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(Person, person.id).email == person.email
      assert Repo.get_by(PersonToken, person_id: person.id)
    end

    test "does not update email if token expired", %{person: person, token: token} do
      {1, nil} = Repo.update_all(PersonToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert People.update_person_email(person, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(Person, person.id).email == person.email
      assert Repo.get_by(PersonToken, person_id: person.id)
    end
  end

  describe "change_person_password/3" do
    test "returns a person changeset" do
      assert %Ecto.Changeset{} = changeset = People.change_person_password(%Person{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        People.change_person_password(
          %Person{},
          %{
            "password" => "NewValidPass123!"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "NewValidPass123!"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_person_password/2" do
    setup do
      %{person: person_fixture()}
    end

    test "validates password", %{person: person} do
      {:error, changeset} =
        People.update_person_password(person, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: [
                 "at least one digit or punctuation character",
                 "at least one upper case character",
                 "should be at least 12 character(s)"
               ],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{person: person} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        People.update_person_password(person, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{person: person} do
      {:ok, {person, expired_tokens}} =
        People.update_person_password(person, %{
          password: "NewValidPass123!"
        })

      assert expired_tokens == []
      assert is_nil(person.password)
      assert People.get_person_by_email_and_password(person.email, "NewValidPass123!")
    end

    test "deletes all tokens for the given person", %{person: person} do
      _ = People.generate_person_session_token(person)

      {:ok, {_, _}} =
        People.update_person_password(person, %{
          password: "NewValidPass123!"
        })

      refute Repo.get_by(PersonToken, person_id: person.id)
    end
  end

  describe "generate_person_session_token/1" do
    setup do
      %{person: person_fixture()}
    end

    test "generates a token", %{person: person} do
      token = People.generate_person_session_token(person)
      assert person_token = Repo.get_by(PersonToken, token: token)
      assert person_token.context == "session"
      assert person_token.authenticated_at != nil

      # Creating the same token for another person should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%PersonToken{
          token: person_token.token,
          person_id: person_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given person in new token", %{person: person} do
      person = %{person | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = People.generate_person_session_token(person)
      assert person_token = Repo.get_by(PersonToken, token: token)
      assert person_token.authenticated_at == person.authenticated_at
      assert DateTime.compare(person_token.inserted_at, person.authenticated_at) == :gt
    end
  end

  describe "get_person_by_session_token/1" do
    setup do
      person = person_fixture()
      token = People.generate_person_session_token(person)
      %{person: person, token: token}
    end

    test "returns person by token", %{person: person, token: token} do
      assert {session_person, token_inserted_at} = People.get_person_by_session_token(token)
      assert session_person.id == person.id
      assert session_person.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return person for invalid token" do
      refute People.get_person_by_session_token("oops")
    end

    test "does not return person for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(PersonToken, set: [inserted_at: dt, authenticated_at: dt])
      refute People.get_person_by_session_token(token)
    end
  end

  describe "get_person_by_magic_link_token/1" do
    setup do
      person = person_fixture()
      {encoded_token, _hashed_token} = generate_person_magic_link_token(person)
      %{person: person, token: encoded_token}
    end

    test "returns person by token", %{person: person, token: token} do
      assert session_person = People.get_person_by_magic_link_token(token)
      assert session_person.id == person.id
    end

    test "does not return person for invalid token" do
      refute People.get_person_by_magic_link_token("oops")
    end

    test "does not return person for expired token", %{token: token} do
      {1, nil} = Repo.update_all(PersonToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute People.get_person_by_magic_link_token(token)
    end
  end

  describe "login_person_by_magic_link/1" do
    test "confirms person and expires tokens" do
      person = unconfirmed_person_fixture()
      refute person.confirmed_at
      {encoded_token, hashed_token} = generate_person_magic_link_token(person)

      assert {:ok, {person, [%{token: ^hashed_token}]}} =
               People.login_person_by_magic_link(encoded_token)

      assert person.confirmed_at
    end

    test "returns person and (deleted) token for confirmed person" do
      person = person_fixture()
      assert person.confirmed_at
      {encoded_token, _hashed_token} = generate_person_magic_link_token(person)
      assert {:ok, {^person, []}} = People.login_person_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = People.login_person_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed person has password set" do
      person = unconfirmed_person_fixture()
      {1, nil} = Repo.update_all(Person, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_person_magic_link_token(person)

      assert_raise RuntimeError, ~r/magic link sign in is not allowed/, fn ->
        People.login_person_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_person_session_token/1" do
    test "deletes the token" do
      person = person_fixture()
      token = People.generate_person_session_token(person)
      assert People.delete_person_session_token(token) == :ok
      refute People.get_person_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{person: unconfirmed_person_fixture()}
    end

    test "sends token through notification", %{person: person} do
      token =
        extract_person_token(fn url ->
          People.deliver_login_instructions(person, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert person_token = Repo.get_by(PersonToken, token: :crypto.hash(:sha256, token))
      assert person_token.person_id == person.id
      assert person_token.sent_to == person.email
      assert person_token.context == "login"
    end
  end

  describe "set_person_role/2" do
    setup do
      %{person: person_fixture()}
    end

    test "promotes a person to owner", %{person: person} do
      assert person.role == :user
      assert {:ok, updated} = People.set_person_role(person, :owner)
      assert updated.role == :owner
    end

    test "demotes a person back to user", %{person: person} do
      {:ok, owner} = People.set_person_role(person, :owner)
      assert {:ok, updated} = People.set_person_role(owner, :user)
      assert updated.role == :user
    end

    test "rejects invalid roles", %{person: person} do
      assert {:error, changeset} = People.set_person_role(person, :admin)
      assert %{role: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "inspect/2 for the Person module" do
    test "does not include password" do
      refute inspect(%Person{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "delete_remote_person/1" do
    @remote_uri "https://remote.example.com/users/alice"

    defp insert_remote_person do
      {:ok, person} =
        People.upsert_remote_person(%{
          uri: @remote_uri,
          public_key: "fake-key",
          username: "alice",
          display_name: "Alice"
        })

      person
    end

    test "deletes the person record and returns :ok" do
      person = insert_remote_person()

      assert :ok = People.delete_remote_person(person)
      assert is_nil(Revix.Repo.get_by(Person, uri: @remote_uri))
    end

    test "cascades to entries authored by the person" do
      person = insert_remote_person()

      {:ok, entry} =
        Revix.Entries.create_inbound_note(%{
          uri: "#{@remote_uri}/notes/1",
          url: "#{@remote_uri}/notes/1",
          author_uri: @remote_uri,
          content: "<p>Hi</p>",
          published_at_utc: ~U[2026-05-14 10:00:00Z]
        })

      assert :ok = People.delete_remote_person(person)
      assert is_nil(Revix.Repo.get_by(Revix.Entries.Entry, id: entry.id))
    end

    test "cascades to likes authored by the person" do
      person = insert_remote_person()

      Revix.Likes.upsert_inbound_like(%{
        author_uri: @remote_uri,
        object_uri: "https://example.com/entries/abc",
        like_uri: "#{@remote_uri}/likes/1"
      })

      assert :ok = People.delete_remote_person(person)
      refute Revix.Repo.exists?(from l in Revix.Likes.Like, where: l.author_uri == ^@remote_uri)
    end

    test "cascades to follows where person is follower" do
      person = insert_remote_person()

      Revix.Follows.upsert_inbound_follow(%{
        uri: "#{@remote_uri}/follows/1",
        follower_uri: @remote_uri,
        following_uri: "https://local.example.com/people/1"
      })

      assert :ok = People.delete_remote_person(person)

      refute Revix.Repo.exists?(
               from f in Revix.Follows.Follow, where: f.follower_uri == ^@remote_uri
             )
    end

    test "cascades to follows where person is being followed" do
      person = insert_remote_person()
      local = person_fixture()

      Revix.Follows.upsert_inbound_follow(%{
        uri: "#{local.uri}/follows/1",
        follower_uri: local.uri,
        following_uri: @remote_uri
      })

      assert :ok = People.delete_remote_person(person)

      refute Revix.Repo.exists?(
               from f in Revix.Follows.Follow, where: f.following_uri == ^@remote_uri
             )
    end

    test "cascades to entry_people rows for the person" do
      person = insert_remote_person()
      local = person_fixture()
      checkin = Revix.EntriesFixtures.checkin_fixture(%{author_uri: local.uri})

      Revix.Repo.insert!(%Revix.EntryPeople.EntryPerson{
        id: Revix.Ecto.Base58Id.autogenerate(),
        entry_uri: checkin.uri,
        person_uri: @remote_uri,
        type: :companion,
        origin: :remote
      })

      assert :ok = People.delete_remote_person(person)

      refute Revix.Repo.exists?(
               from ep in Revix.EntryPeople.EntryPerson, where: ep.person_uri == ^@remote_uri
             )
    end

    test "returns {:error, :local_person} for a local person" do
      local = person_fixture()
      assert {:error, :local_person} = People.delete_remote_person(local)
      assert Revix.Repo.get_by(Person, id: local.id)
    end
  end

  describe "get_or_fetch_person_by_uri/2" do
    import Revix.FederationFixtures

    test "returns the local person without an HTTP fetch" do
      local = person_fixture()

      Req.Test.stub(:federation, fn _conn -> raise "unexpected federation HTTP call" end)

      assert {:ok, person} = People.get_or_fetch_person_by_uri(local.uri)
      assert person.id == local.id
    end

    test "fetches and stores a new remote person on cache miss" do
      uri = remote_actor_uri()
      stub_actor(uri)

      assert {:ok, person} = People.get_or_fetch_person_by_uri(uri)
      assert person.uri == uri
      assert person.origin == :remote
    end

    test "uses the actor document's own id when it matches the fetch origin" do
      profile_url = "https://remote.example.com/@alice"
      canonical_uri = remote_actor_uri()
      stub_actor(profile_url, %{"id" => canonical_uri})

      assert {:ok, person} = People.get_or_fetch_person_by_uri(profile_url)
      assert person.uri == canonical_uri
    end

    test "rejects an actor document whose id is a different origin" do
      profile_url = "https://remote.example.com/@alice"
      stub_actor(profile_url, %{"id" => "https://evil.example.com/users/alice"})

      assert {:error, :actor_id_origin_mismatch} =
               People.get_or_fetch_person_by_uri(profile_url)

      refute Revix.Repo.get_by(Person, uri: "https://evil.example.com/users/alice")
    end

    test "returns the cached person without refetching when not stale" do
      uri = remote_actor_uri()
      stub_actor(uri)
      {:ok, cached} = People.get_or_fetch_person_by_uri(uri)

      Req.Test.stub(:federation, fn _conn -> raise "unexpected federation HTTP call" end)

      assert {:ok, person} = People.get_or_fetch_person_by_uri(uri)
      assert person.id == cached.id
    end

    test "force_refresh: true refetches even when not stale" do
      uri = remote_actor_uri()
      stub_actor(uri)
      {:ok, _cached} = People.get_or_fetch_person_by_uri(uri)

      stub_actor(uri, %{"name" => "Alice Updated"})

      assert {:ok, person} = People.get_or_fetch_person_by_uri(uri, force_refresh: true)
      assert person.display_name == "Alice Updated"
    end
  end
end
