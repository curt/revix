defmodule Revix.Entries.TimezoneBackfill do
  @moduledoc """
  One-off admin task, run from IEx: fixes the timezone of checkins recorded
  as Etc/UTC near a place.
  """
  import Ecto.Query
  import Geo.PostGIS
  alias Revix.Repo
  alias Revix.Entries.Entry
  alias Revix.Places.Place

  @doc """
  Backfills the timezone and local datetimes for checkins within a given radius
  whose timezone is currently "Etc/UTC". Intended for one-off admin use from IEx.

  Source can be a `%Place{}` (uses its coordinates) or a `{lat, lon}` tuple.
  Radius defaults to 20,000 metres (20 km).

  Returns `{:ok, updated_count}` or `{:error, :invalid_timezone}`.

  ## Examples

      iex> Revix.Entries.backfill_timezone(place, "America/New_York")
      {:ok, 5}

      iex> Revix.Entries.backfill_timezone({40.7128, -74.0060}, "America/New_York", radius: 10_000)
      {:ok, 3}
  """
  def backfill_timezone(source, timezone, opts \\ []) do
    if timezone not in Tzdata.zone_list() do
      {:error, :invalid_timezone}
    else
      radius = Keyword.get(opts, :radius, 20_000)
      center = resolve_center(source)

      entries =
        Repo.all(
          from e in Entry,
            join: p in Place,
            on: e.place_uri == p.uri,
            where: e.type == :checkin,
            where: e.origin == :local,
            where: e.starts_tz == "Etc/UTC",
            where: st_dwithin_in_meters(p.coordinates, ^center, ^radius)
        )

      Repo.transaction(fn ->
        Enum.reduce(entries, 0, fn entry, count ->
          fields = backfill_fields(entry, timezone)
          entry |> Ecto.Changeset.change(fields) |> Repo.update!()
          count + 1
        end)
      end)
    end
  end

  defp resolve_center(%Place{coordinates: coords}), do: coords

  defp resolve_center({lat, lon}),
    do: %Geo.Point{coordinates: {lon, lat}, srid: 4326}

  defp backfill_fields(entry, timezone) do
    %{starts_tz: timezone, published_tz: timezone}
    |> maybe_put_starts_local(entry, timezone)
    |> maybe_put_published_local(entry, timezone)
    |> maybe_put_ends_local(entry, timezone)
  end

  defp maybe_put_starts_local(fields, %{starts_at_utc: nil}, _tz), do: fields

  defp maybe_put_starts_local(fields, entry, tz) do
    Map.put(
      fields,
      :starts_at_local,
      entry.starts_at_utc |> DateTime.shift_zone!(tz) |> DateTime.to_naive()
    )
  end

  defp maybe_put_published_local(fields, %{published_at_utc: nil}, _tz), do: fields

  defp maybe_put_published_local(fields, entry, tz) do
    Map.put(
      fields,
      :published_at_local,
      entry.published_at_utc |> DateTime.shift_zone!(tz) |> DateTime.to_naive()
    )
  end

  defp maybe_put_ends_local(fields, %{ends_at_utc: nil}, _tz), do: fields

  defp maybe_put_ends_local(fields, entry, tz) do
    fields
    |> Map.put(
      :ends_at_local,
      entry.ends_at_utc |> DateTime.shift_zone!(tz) |> DateTime.to_naive()
    )
    |> Map.put(:ends_tz, tz)
  end
end
