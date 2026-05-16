defmodule Revix.Places do
  import Ecto.Query
  import Geo.PostGIS
  alias Revix.Repo
  alias Revix.Places.Place
  alias Revix.People.Person
  alias Revix.Entries.Entry

  def get_local_places() do
    Repo.all(from(p in Place, where: p.origin == :local, order_by: p.name))
  end

  def get_local_places_for_sitemap() do
    Repo.all(from(p in Place, where: p.origin == :local, order_by: [desc: p.inserted_at]))
  end

  def search_local_places(query) when is_binary(query) do
    pattern = "%#{query}%"

    Repo.all(
      from(p in Place,
        where: p.origin == :local and ilike(p.name, ^pattern),
        order_by: p.name,
        limit: 10
      )
    )
  end

  @doc """
  Returns all local places the given person has checked in to.

  Each place is returned at most once, even if the person has multiple checkins there.
  """
  def get_places_for_person(%Person{} = person) do
    from(p in Place,
      join: e in Entry,
      on: e.place_uri == p.uri,
      where:
        p.origin == :local and
          e.type == :checkin and
          e.origin == :local and
          e.author_uri == ^person.uri,
      distinct: true
    )
    |> Repo.all()
  end

  def get_local_places_near(%Place{} = place, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    radius = Keyword.get(opts, :radius, 20000)

    places =
      from(p in Place,
        where: p.origin == :local,
        where: p.id != ^place.id,
        where: st_dwithin_in_meters(p.coordinates, ^place.coordinates, ^radius),
        order_by: st_distance(p.coordinates, ^place.coordinates),
        select: %{place: p, distance: st_distance(p.coordinates, ^place.coordinates)}
      )
      |> limit(^limit)
      |> Repo.all()

    places
  end

  def get_local_place(id) do
    place_ok_or_not_found(Repo.get_by(Place, id: id, origin: :local))
  end

  def get_local_place_by_uri(uri) do
    place_ok_or_not_found(Repo.get_by(Place, uri: uri, origin: :local))
  end

  def change_place(attrs \\ %{}) do
    Place.create_changeset(%Place{}, attrs)
  end

  def change_place_for_edit(%Place{} = place) do
    {lon, lat} = place.coordinates.coordinates

    Place.create_changeset(place, %{
      "name" => place.name,
      "latitude" => lat,
      "longitude" => lon,
      "osm_type" => place.osm_type && to_string(place.osm_type),
      "osm_id" => place.osm_id
    })
  end

  def update_local_place(%Place{} = place, attrs) do
    place |> Place.create_changeset(attrs) |> Repo.update()
  end

  def unlink_place_osm(%Place{} = place) do
    place |> Ecto.Changeset.change(osm_type: nil, osm_id: nil) |> Repo.update()
  end

  def create_local_place(attrs, uri_fn, url_fn) do
    id = Revix.Ecto.Base58Id.autogenerate()
    name = attrs["name"] || attrs[:name] || ""
    slug = Place.slugify(name)

    %Place{
      id: id,
      origin: :local,
      uri: uri_fn.(id),
      url: url_fn.(id, slug)
    }
    |> Place.create_changeset(attrs)
    |> Repo.insert()
  end

  def upsert_remote_place(attrs) do
    case Repo.get_by(Place, uri: attrs.uri) do
      nil ->
        %Place{origin: :remote, uri: attrs.uri, url: attrs[:url] || attrs.uri}
        |> Place.create_changeset(attrs)
        |> Repo.insert()

      existing ->
        {:ok, existing}
    end
  end

  def get_local_place_by_osm(osm_type, osm_id) when is_atom(osm_type) and is_integer(osm_id) do
    Repo.one(
      from(p in Place,
        where: p.origin == :local and p.osm_type == ^osm_type and p.osm_id == ^osm_id
      )
    )
  end

  @doc """
  Returns local DB places within the search radius synchronously.
  Use this for an immediate partial result while OSM is fetched async.
  """
  def search_nearby_db(lat, lon, accuracy) when is_float(lat) and is_float(lon) do
    radius = max(100, round(accuracy)) + 100
    point = %Geo.Point{coordinates: {lon, lat}, srid: 4326}

    db_places =
      from(p in Place,
        where: p.origin == :local,
        where: st_dwithin_in_meters(p.coordinates, ^point, ^radius),
        order_by: st_distance(p.coordinates, ^point),
        select: %{
          place: p,
          distance: st_distance_in_meters(p.coordinates, ^point)
        }
      )
      |> Repo.all()

    Enum.map(db_places, fn %{place: p, distance: d} ->
      {p_lon, p_lat} = p.coordinates.coordinates

      %{
        source: :db,
        id: p.id,
        name: p.name,
        lat: p_lat,
        lon: p_lon,
        distance: d,
        osm_type: p.osm_type,
        osm_id: p.osm_id
      }
    end)
  end

  @doc """
  Returns OSM places near the given coordinates. Blocks on the Overpass HTTP call.
  """
  def search_nearby_osm(lat, lon, accuracy) do
    radius = max(100, round(accuracy)) + 100

    case Revix.Overpass.search_nearby(lat, lon, radius) do
      {:ok, results} -> results
      {:error, _} -> []
    end
  end

  @doc """
  Merges DB and OSM results, deduplicating OSM entries that already exist locally.
  """
  def merge_place_results(db_results, osm_results) do
    limit = Application.get_env(:revix, :places)[:nearby_result_limit] || 20
    merge_results(db_results, osm_results) |> Enum.take(limit)
  end

  defp merge_results(db_results, osm_results) do
    db_osm_keys =
      db_results
      |> Enum.filter(fn r -> r.osm_type && r.osm_id end)
      |> MapSet.new(fn r -> {r.osm_type, r.osm_id} end)

    deduplicated_osm =
      Enum.reject(osm_results, fn r ->
        r.osm_type && r.osm_id && MapSet.member?(db_osm_keys, {r.osm_type, r.osm_id})
      end)

    (db_results ++ deduplicated_osm)
    |> Enum.sort_by(& &1.distance)
  end

  defp place_ok_or_not_found(%Place{} = place), do: {:ok, place}

  defp place_ok_or_not_found(nil), do: {:error, :not_found}
end
