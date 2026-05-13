defmodule Revix.Overpass do
  @overpass_url "https://overpass-api.de/api/interpreter"

  def search_nearby(lat, lon, radius)
      when is_float(lat) and is_float(lon) and is_number(radius) do
    query = build_query(lat, lon, radius)

    plug = Application.get_env(:revix, :overpass_req_plug)
    opts = [form: [data: query], receive_timeout: 30_000]
    opts = if plug, do: Keyword.put(opts, :plug, plug), else: opts

    case Req.post(@overpass_url, opts) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_elements(body, lat, lon)}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_query(lat, lon, radius) do
    around = "around:#{radius},#{lat},#{lon}"

    """
    [out:json][timeout:25];
    (
      nwr(#{around})[name][~"^(tourism|amenity|historic|leisure|shop)$"~"."];
      nwr(#{around})[name][aeroway=aerodrome];
      nwr(#{around})[name][railway=station];
      node(#{around})[name][highway=bus_stop];
      node(#{around})[name][railway=tram_stop];
    );
    out center;
    """
  end

  def fetch_element(osm_type, osm_id)
      when osm_type in [:node, :way, :relation] and is_integer(osm_id) do
    query = """
    [out:json][timeout:25];
    #{osm_type}(#{osm_id});
    out center;
    """

    plug = Application.get_env(:revix, :overpass_req_plug)
    opts = [form: [data: query], receive_timeout: 30_000]
    opts = if plug, do: Keyword.put(opts, :plug, plug), else: opts

    case Req.post(@overpass_url, opts) do
      {:ok, %{status: 200, body: %{"elements" => [element | _]}}} ->
        parse_single_element(element)

      {:ok, %{status: 200, body: %{"elements" => []}}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_single_element(element) do
    name = get_in(element, ["tags", "name"])
    {lat, lon} = element_coordinates(element)

    if name && lat && lon do
      {:ok, %{name: name, lat: lat, lon: lon}}
    else
      {:error, :not_found}
    end
  end

  def parse_elements(%{"elements" => elements}, origin_lat, origin_lon) do
    elements
    |> Enum.map(fn el -> parse_element(el, origin_lat, origin_lon) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.distance)
  end

  def parse_elements(_, _, _), do: []

  defp parse_element(el, origin_lat, origin_lon) do
    name = get_in(el, ["tags", "name"])
    type = el["type"]
    {lat, lon} = element_coordinates(el)

    if name && lat && lon && type in ["node", "way", "relation"] do
      %{
        source: :osm,
        id: nil,
        name: name,
        lat: lat,
        lon: lon,
        distance: haversine(origin_lat, origin_lon, lat, lon),
        osm_type: String.to_existing_atom(type),
        osm_id: el["id"]
      }
    end
  end

  defp element_coordinates(%{"type" => "node", "lat" => lat, "lon" => lon}), do: {lat, lon}

  defp element_coordinates(%{"center" => %{"lat" => lat, "lon" => lon}}), do: {lat, lon}

  defp element_coordinates(_), do: {nil, nil}

  defp haversine(lat1, lon1, lat2, lon2) do
    r = 6_371_000
    dlat = deg_to_rad(lat2 - lat1)
    dlon = deg_to_rad(lon2 - lon1)
    rlat1 = deg_to_rad(lat1)
    rlat2 = deg_to_rad(lat2)

    a = :math.sin(dlat / 2) ** 2 + :math.cos(rlat1) * :math.cos(rlat2) * :math.sin(dlon / 2) ** 2
    2 * r * :math.asin(:math.sqrt(a))
  end

  defp deg_to_rad(deg), do: deg * :math.pi() / 180
end
