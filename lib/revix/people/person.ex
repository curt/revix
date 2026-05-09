defmodule Revix.People.Person do
  use Revix.Schema
  use Waffle.Ecto.Schema
  import Ecto.Changeset

  schema "people" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    field :origin, Revix.Ecto.Origin
    field :uri, :string
    field :url, :string
    field :username, :string
    field :display_name, :string
    field :public_key, :string
    field :private_key, Revix.Ecto.EncryptedBinary, redact: true
    field :role, Revix.Ecto.Role, default: :user
    field :avatar, Revix.Uploaders.Avatar.Type

    timestamps(type: :utc_datetime)
  end

  @doc """
  A person changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(person, attrs, opts \\ []) do
    person
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> maybe_generate_required_fields(person, opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Revix.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  defp maybe_generate_required_fields(_, _, _)

  defp maybe_generate_required_fields(%{valid?: false} = changeset, _, _), do: changeset

  defp maybe_generate_required_fields(changeset, %{id: id}, _) when is_binary(id), do: changeset

  defp maybe_generate_required_fields(changeset, _, opts) do
    id = Revix.Ecto.Base58Id.autogenerate()
    {public_key, private_key} = create_rsa_pair()
    uri_fn = Keyword.fetch!(opts, :uri_fn)
    url_fn = Keyword.fetch!(opts, :url_fn)

    changeset
    |> change(%{
      id: id,
      uri: uri_fn.(id),
      url: url_fn.(id, get_field(changeset, :username)),
      origin: :local,
      public_key: public_key,
      private_key: private_key
    })
  end

  defp create_rsa_pair() do
    private_key = X509.PrivateKey.new_rsa(2048)
    public_key = X509.PublicKey.derive(private_key)
    {X509.PublicKey.to_pem(public_key), X509.PrivateKey.to_pem(private_key)}
  end

  @doc """
  A person changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(person, attrs, opts \\ []) do
    person
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/,
      message: "at least one digit or punctuation character"
    )
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(person) do
    now = DateTime.utc_now(:second)
    change(person, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no person or the person doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Revix.People.Person{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  def avatar_changeset(person, params) do
    person
    |> cast_attachments(params, [:avatar])
    |> validate_required([:avatar])
  end

  def role_changeset(person, attrs) do
    person
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, Revix.Ecto.Role.values())
  end

  def display_name_changeset(person, attrs) do
    max = Application.get_env(:revix, :person)[:display_name_max_length]

    person
    |> cast(attrs, [:display_name])
    |> validate_length(:display_name, max: max)
  end

  def remote_changeset(person, attrs) do
    person
    |> cast(attrs, [:id, :uri, :url, :username, :display_name, :public_key])
    |> validate_required([:id, :uri])
    |> put_change(:origin, :remote)
    |> put_synthetic_email()
    |> put_synthetic_url()
    |> unique_constraint(:uri)
    |> unique_constraint(:email)
  end

  defp put_synthetic_email(%{valid?: false} = changeset), do: changeset

  defp put_synthetic_email(changeset) do
    case get_field(changeset, :email) do
      nil ->
        uri = get_field(changeset, :uri)
        hash = :crypto.hash(:sha256, uri) |> Base.encode16(case: :lower)
        put_change(changeset, :email, "#{hash}@example.invalid")

      _ ->
        changeset
    end
  end

  defp put_synthetic_url(%{valid?: false} = changeset), do: changeset

  defp put_synthetic_url(changeset) do
    case get_field(changeset, :url) do
      nil -> put_change(changeset, :url, get_field(changeset, :uri))
      _ -> changeset
    end
  end
end
