defmodule Revix.People do
  @moduledoc """
  The People context.
  """

  import Ecto.Query, warn: false
  alias Revix.Repo

  alias Revix.People.{Person, PersonToken, PersonNotifier}

  ## Database getters

  @doc """
  Gets a person by email.

  ## Examples

      iex> get_person_by_email("foo@example.com")
      %Person{}

      iex> get_person_by_email("unknown@example.com")
      nil

  """
  def get_person_by_email(email) when is_binary(email) do
    Repo.get_by(Person, email: email)
  end

  @doc """
  Gets a person by email and password.

  ## Examples

      iex> get_person_by_email_and_password("foo@example.com", "correct_password")
      %Person{}

      iex> get_person_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_person_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    person = Repo.get_by(Person, email: email)
    if Person.valid_password?(person, password), do: person
  end

  @doc """
  Gets a single person.

  Raises `Ecto.NoResultsError` if the Person does not exist.

  ## Examples

      iex> get_person!(123)
      %Person{}

      iex> get_person!(456)
      ** (Ecto.NoResultsError)

  """
  def get_person!(id), do: Repo.get!(Person, id)

  def get_local_person(id) do
    person_ok_or_not_found(Repo.get_by(Person, id: id, origin: :local))
  end

  def get_local_person_by_username(username) do
    person_ok_or_not_found(Repo.get_by(Person, username: username, origin: :local))
  end

  def get_local_person_by_uri(uri) do
    person_ok_or_not_found(Repo.get_by(Person, uri: uri, origin: :local))
  end

  defp person_ok_or_not_found(%Person{} = person), do: {:ok, person}

  defp person_ok_or_not_found(nil), do: {:error, :not_found}

  @doc """
  Searches for people by display name or URI, excluding a given URI.

  Returns up to 10 people whose display_name matches the query (case-insensitive),
  or whose URI starts with the query. The exclude_uri person is never returned,
  which is used to prevent a user from searching for themselves.
  """
  def search_people(query, exclude_uri) when is_binary(query) and is_binary(exclude_uri) do
    pattern = "%#{query}%"

    Repo.all(
      from p in Person,
        where:
          p.uri != ^exclude_uri and
            (ilike(p.display_name, ^pattern) or ilike(p.uri, ^pattern) or
               ilike(p.username, ^pattern)),
        order_by: [asc: p.display_name],
        limit: 10
    )
  end

  ## Person registration

  @doc """
  Registers a person.

  ## Examples

      iex> register_person(%{field: value})
      {:ok, %Person{}}

      iex> register_person(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_person(attrs, uri_fn, url_fn) do
    %Person{}
    |> Person.email_changeset(attrs, uri_fn: uri_fn, url_fn: url_fn)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the person is in sudo mode.

  The person is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(person, minutes \\ -20)

  def sudo_mode?(%Person{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_person, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the person email.

  See `Revix.People.Person.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_person_email(person)
      %Ecto.Changeset{data: %Person{}}

  """
  def change_person_email(person, attrs \\ %{}, opts \\ []) do
    Person.email_changeset(person, attrs, opts)
  end

  @doc """
  Updates the person email using the given token.

  If the token matches, the person email is updated and the token is deleted.
  """
  def update_person_email(person, token) do
    context = "change:#{person.email}"

    Repo.transact(fn ->
      with {:ok, query} <- PersonToken.verify_change_email_token_query(token, context),
           %PersonToken{sent_to: email} <- Repo.one(query),
           {:ok, person} <- Repo.update(Person.email_changeset(person, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(PersonToken, where: [person_id: ^person.id, context: ^context])) do
        {:ok, person}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the person password.

  See `Revix.People.Person.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_person_password(person)
      %Ecto.Changeset{data: %Person{}}

  """
  def change_person_password(person, attrs \\ %{}, opts \\ []) do
    Person.password_changeset(person, attrs, opts)
  end

  @doc """
  Updates the person password.

  Returns a tuple with the updated person, as well as a list of expired tokens.

  ## Examples

      iex> update_person_password(person, %{password: ...})
      {:ok, {%Person{}, [...]}}

      iex> update_person_password(person, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_person_password(person, attrs) do
    person
    |> Person.password_changeset(attrs)
    |> update_person_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_person_session_token(person) do
    {token, person_token} = PersonToken.build_session_token(person)
    Repo.insert!(person_token)
    token
  end

  @doc """
  Gets the person with the given signed token.

  If the token is valid `{person, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_person_by_session_token(token) do
    {:ok, query} = PersonToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the person with the given magic link token.
  """
  def get_person_by_magic_link_token(token) do
    with {:ok, query} <- PersonToken.verify_magic_link_token_query(token),
         {person, _token} <- Repo.one(query) do
      person
    else
      _ -> nil
    end
  end

  def change_person_display_name(person, attrs \\ %{}) do
    Person.display_name_changeset(person, attrs)
  end

  def update_person_display_name(person, attrs) do
    person
    |> Person.display_name_changeset(attrs)
    |> Repo.update()
  end

  def change_person_avatar(person, attrs \\ %{}) do
    Person.avatar_changeset(person, attrs)
  end

  def update_person_avatar(person, attrs \\ %{}) do
    person
    |> Person.avatar_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Logs the person in by magic link.

  There are three cases to consider:

  1. The person has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The person has not confirmed their email and no password is set.
     In this case, the person gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The person has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_person_by_magic_link(token) do
    {:ok, query} = PersonToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%Person{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link sign in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%Person{confirmed_at: nil} = person, _token} ->
        person
        |> Person.confirm_changeset()
        |> update_person_and_delete_all_tokens()

      {person, token} ->
        Repo.delete!(token)
        {:ok, {person, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given person.

  ## Examples

      iex> deliver_person_update_email_instructions(person, current_email, &url(~p"/people/settings/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_person_update_email_instructions(
        %Person{} = person,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, person_token} =
      PersonToken.build_email_token(person, "change:#{current_email}")

    Repo.insert!(person_token)
    PersonNotifier.deliver_update_email_instructions(person, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given person.
  """
  def deliver_login_instructions(%Person{} = person, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, person_token} = PersonToken.build_email_token(person, "login")
    Repo.insert!(person_token)
    PersonNotifier.deliver_login_instructions(person, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_person_session_token(token) do
    Repo.delete_all(from(PersonToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Roles

  @doc """
  Sets the role for a person.

  Callable from `iex`:

      person = Revix.People.get_person_by_email("owner@example.com")
      Revix.People.set_person_role(person, :owner)

  """
  def set_person_role(%Person{} = person, role) when is_atom(role) do
    person
    |> Person.role_changeset(%{role: role})
    |> Repo.update()
  end

  ## Token helper

  defp update_person_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, person} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(PersonToken, person_id: person.id)

        Repo.delete_all(
          from(t in PersonToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id))
        )

        {:ok, {person, tokens_to_expire}}
      end
    end)
  end
end
