defmodule Revix.PeopleFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Revix.People` context.
  """

  import Ecto.Query

  alias Revix.People
  alias Revix.People.Scope

  def unique_person_email, do: "person#{System.unique_integer()}@example.com"
  def valid_person_password, do: "Hello world!123"

  def valid_person_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_person_email()
    })
  end

  def unconfirmed_person_fixture(attrs \\ %{}) do
    {:ok, person} =
      attrs
      |> valid_person_attributes()
      |> People.register_person(
        fn id -> "http://localhost:4000/people/#{id}" end,
        fn id, _username -> "http://localhost:4000/people/#{id}" end
      )

    person
  end

  def person_fixture(attrs \\ %{}) do
    person = unconfirmed_person_fixture(attrs)

    token =
      extract_person_token(fn url ->
        People.deliver_login_instructions(person, url)
      end)

    {:ok, {person, _expired_tokens}} =
      People.login_person_by_magic_link(token)

    person
  end

  def person_scope_fixture do
    person = person_fixture()
    person_scope_fixture(person)
  end

  def person_scope_fixture(person) do
    Scope.for_person(person)
  end

  def set_password(person) do
    {:ok, {person, _expired_tokens}} =
      People.update_person_password(person, %{password: valid_person_password()})

    person
  end

  def extract_person_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Revix.Repo.update_all(
      from(t in People.PersonToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_person_magic_link_token(person) do
    {encoded_token, person_token} = People.PersonToken.build_email_token(person, "login")
    Revix.Repo.insert!(person_token)
    {encoded_token, person_token.token}
  end

  def offset_person_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Revix.Repo.update_all(
      from(ut in People.PersonToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
