defmodule Revix.Entries.Entry do
  use Revix.Schema
  import Ecto.Changeset
  alias Revix.Ecto.EntryType
  alias Revix.Ecto.Origin
  alias Revix.EntryPeople.EntryPerson
  alias Revix.People.Person
  alias Revix.Places.Place

  schema "entries" do
    field :uri, :string
    field :url, :string

    field :type, EntryType

    field :name, :string
    field :content, :string
    field :content_html, :string
    field :summary, :string
    field :summary_html, :string
    field :context, :string

    field :origin, Origin

    # Published datetime - all three components
    field :published_at_utc, :utc_datetime
    field :published_at_local, :naive_datetime
    field :published_tz, :string

    # Starts datetime - all three components
    field :starts_at_utc, :utc_datetime
    field :starts_at_local, :naive_datetime
    field :starts_tz, :string

    # Ends datetime - all three components
    field :ends_at_utc, :utc_datetime
    field :ends_at_local, :naive_datetime
    field :ends_tz, :string

    # URI-based references (no foreign key constraints)
    field :author_uri, :string
    field :in_reply_to_uri, :string
    field :place_uri, :string

    # Virtual associations (no foreign key constraints)
    has_one :author, Person, foreign_key: :uri, references: :author_uri
    has_one :in_reply_to, __MODULE__, foreign_key: :uri, references: :in_reply_to_uri
    has_one :place, Place, foreign_key: :uri, references: :place_uri

    has_many :replies, __MODULE__, foreign_key: :in_reply_to_uri, references: :uri

    has_many :companions, EntryPerson,
      foreign_key: :entry_uri,
      references: :uri,
      where: [type: :companion]

    has_many :entry_images, Revix.Media.EntryImage
    has_many :images, through: [:entry_images, :image]

    timestamps()
  end

  def update_checkin_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:content])
    |> maybe_convert_content_to_html()
  end

  def comment_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:content, :published_tz])
    |> validate_required([:content, :published_tz])
    |> validate_timezone(:published_tz)
    |> maybe_convert_content_to_html()
    |> set_comment_published_at()
    |> set_comment_context()
  end

  def update_comment_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:content])
    |> validate_required([:content])
    |> maybe_convert_content_to_html()
  end

  def checkin_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:content, :starts_at_local, :starts_tz])
    |> validate_required([:starts_at_local, :starts_tz])
    |> validate_timezone(:starts_tz)
    |> maybe_convert_content_to_html()
    |> compute_starts_at_utc()
    |> set_published_at()
    |> set_context()
  end

  defp validate_timezone(changeset, field) do
    validate_change(changeset, field, fn _, tz ->
      if tz in Tzdata.zone_list() do
        []
      else
        [{field, "is not a valid timezone"}]
      end
    end)
  end

  defp maybe_convert_content_to_html(changeset) do
    case get_change(changeset, :content) do
      nil ->
        changeset

      content ->
        case Earmark.as_html(content, compact_output: true) do
          {:ok, html, _} -> put_change(changeset, :content_html, html)
          {:error, _, _} -> add_error(changeset, :content, "could not be converted to HTML")
        end
    end
  end

  defp compute_starts_at_utc(%{valid?: false} = changeset), do: changeset

  defp compute_starts_at_utc(changeset) do
    case {get_field(changeset, :starts_at_local), get_field(changeset, :starts_tz)} do
      {local, tz} when not is_nil(local) and not is_nil(tz) ->
        utc = local |> DateTime.from_naive!(tz) |> DateTime.shift_zone!("Etc/UTC")
        put_change(changeset, :starts_at_utc, utc)

      _ ->
        changeset
    end
  end

  defp set_published_at(%{valid?: false} = changeset), do: changeset
  defp set_published_at(changeset), do: set_published_at_fields(changeset, :starts_tz)

  defp set_context(changeset), do: set_context_from_field(changeset, :uri)

  def reply?(%__MODULE__{in_reply_to_uri: uri}) when not is_nil(uri), do: true
  def reply?(_), do: false

  def top_level?(%__MODULE__{in_reply_to_uri: nil}), do: true
  def top_level?(_), do: false

  defp set_comment_published_at(%{valid?: false} = changeset), do: changeset
  defp set_comment_published_at(changeset), do: set_published_at_fields(changeset, :published_tz)

  defp set_published_at_fields(changeset, tz_field) do
    case get_field(changeset, tz_field) do
      nil ->
        changeset

      tz ->
        now_utc = DateTime.utc_now(:second)
        now_local = DateTime.shift_zone!(now_utc, tz) |> DateTime.to_naive()

        changeset
        |> put_change(:published_at_utc, now_utc)
        |> put_change(:published_at_local, now_local)
        |> put_change(:published_tz, tz)
    end
  end

  defp set_comment_context(changeset), do: set_context_from_field(changeset, :in_reply_to_uri)

  defp set_context_from_field(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      value -> put_change(changeset, :context, value)
    end
  end
end
