defmodule Revix.Overpass do
  require Logger

  @default_api_url "https://overpass-api.de/api"
  @max_size 67_108_864

  # The nearby search is interactive, so it gives up sooner than a sync.
  @search_limits [query_timeout: 10, receive_timeout: 13_000, max_retries: 1]
  @fetch_limits [query_timeout: 15, receive_timeout: 20_000, max_retries: 2]
  @log_excerpt_length 500

  def search_nearby(lat, lon, radius)
      when is_float(lat) and is_float(lon) and is_number(radius) do
    with {:ok, body} <- post_query(:search_nearby, build_query(lat, lon, radius)) do
      {:ok, parse_elements(body, lat, lon)}
    end
  end

  defp build_query(lat, lon, radius) do
    """
    #{query_settings(:search_nearby)}
    nwr(around:#{radius},#{lat},#{lon})[name]->.named;
    is_in(#{lat},#{lon})->.containing;
    (
      nwr.named[tourism];
      nwr.named[amenity];
      nwr.named[historic];
      nwr.named[leisure];
      nwr.named[shop];
      nwr.named[aeroway=aerodrome];
      nwr.named[railway=station];
      node.named[highway=bus_stop];
      node.named[railway=tram_stop];
      rel(pivot.containing)[name][boundary=administrative][admin_level~"^([6-9]|10)$"];
    );
    out tags center;
    """
  end

  def fetch_element(osm_type, osm_id)
      when osm_type in [:node, :way, :relation] and is_integer(osm_id) do
    kind = {:fetch, osm_type, osm_id}

    query = """
    #{query_settings(kind)}
    #{osm_type}(#{osm_id});
    out tags center;
    """

    with {:ok, body} <- post_query(kind, query) do
      first_element(body)
    end
  end

  defp limits(:search_nearby), do: @search_limits
  defp limits({:fetch, _osm_type, _osm_id}), do: @fetch_limits

  defp query_settings(kind) do
    "[out:json][timeout:#{limits(kind)[:query_timeout]}][maxsize:#{@max_size}];"
  end

  defp first_element(%{"elements" => [element | _]}), do: parse_single_element(element)
  defp first_element(_), do: {:error, :not_found}

  defp post_query(kind, query) do
    plug = Application.get_env(:revix, :overpass_req_plug)
    opts = req_opts(kind) |> Keyword.put(:form, data: query)
    opts = if plug, do: Keyword.put(opts, :plug, plug), else: opts

    started = System.monotonic_time(:millisecond)
    response = Req.post(interpreter_url(), opts)
    elapsed = System.monotonic_time(:millisecond) - started

    log_response(response, "[overpass] #{inspect(kind)}", elapsed)
    handle_response(response)
  end

  defp interpreter_url do
    Application.get_env(:revix, :overpass, [])[:api_url]
    |> api_base()
    |> String.trim_trailing("/")
    |> with_interpreter_path()
  end

  defp api_base(nil), do: @default_api_url
  defp api_base(url), do: url |> String.trim() |> blank_to_default()

  defp blank_to_default(""), do: @default_api_url
  defp blank_to_default(url), do: url

  defp with_interpreter_path(url),
    do: String.replace_suffix(url, "/interpreter", "") <> "/interpreter"

  defp handle_response({:ok, %{status: 200, body: %{"remark" => remark, "elements" => []}}}),
    do: {:error, {:overpass_remark, remark}}

  defp handle_response({:ok, %{status: 200, body: %{"elements" => _} = body}}), do: {:ok, body}
  defp handle_response({:ok, %{status: 200}}), do: {:error, :unexpected_body}
  defp handle_response({:ok, %{status: status}}), do: {:error, {:http_error, status}}
  defp handle_response({:error, reason}), do: {:error, reason}

  defp log_response({:ok, %{status: 200, body: %{"remark" => remark}}}, prefix, ms) do
    Logger.warning("#{prefix} remark (#{ms}ms): #{remark}")
  end

  defp log_response({:ok, %{status: 200, body: %{"elements" => elements}}}, prefix, ms) do
    Logger.debug("#{prefix} #{length(elements)} elements (#{ms}ms)")
  end

  defp log_response({:ok, %{status: 200, body: body}}, prefix, ms) do
    Logger.warning("#{prefix} unexpected body (#{ms}ms): #{excerpt(body)}")
  end

  defp log_response({:ok, %{status: status, body: body} = response}, prefix, ms) do
    retry_after = Req.Response.get_header(response, "retry-after")

    Logger.warning(
      "#{prefix} HTTP #{status} (#{ms}ms)#{retry_after_note(retry_after)}: #{excerpt(body)}"
    )
  end

  defp log_response({:error, reason}, prefix, ms) do
    Logger.warning("#{prefix} transport error (#{ms}ms): #{inspect(reason)}")
  end

  defp retry_after_note([]), do: ""
  defp retry_after_note([value | _]), do: " retry-after=#{value}"

  defp excerpt(body) when is_binary(body) do
    body |> String.replace(~r/\s+/, " ") |> String.slice(0, @log_excerpt_length)
  end

  defp excerpt(body), do: body |> inspect() |> excerpt()

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
        preferred_name: preferred_name(el["tags"], name),
        lat: lat,
        lon: lon,
        distance: haversine(origin_lat, origin_lon, lat, lon),
        osm_type: String.to_existing_atom(type),
        osm_id: el["id"]
      }
    end
  end

  defp preferred_name(tags, name) do
    tags
    |> Map.get("name:#{name_language()}", tags["int_name"])
    |> distinct_name(name)
  end

  defp distinct_name(name, name), do: nil
  defp distinct_name(alternate, _name), do: alternate

  defp name_language, do: Application.get_env(:revix, :overpass, [])[:name_language] || "en"

  defp element_coordinates(%{"type" => "node", "lat" => lat, "lon" => lon}), do: {lat, lon}

  defp element_coordinates(%{"center" => %{"lat" => lat, "lon" => lon}}), do: {lat, lon}

  defp element_coordinates(_), do: {nil, nil}

  defp req_opts(kind) do
    version = Application.spec(:revix, :vsn) || "0"
    config = Application.get_env(:revix, :overpass, [])
    contact = config[:contact_url] || ""
    limits = limits(kind)

    [
      receive_timeout: limits[:receive_timeout],
      retry: :transient,
      max_retries: limits[:max_retries],
      headers: [{"user-agent", "revix/#{version} (#{contact})"}]
    ]
    |> maybe_put_retry_delay(config[:retry_delay])
    |> maybe_put_bearer_token(bearer_token(config))
  end

  defp maybe_put_retry_delay(opts, nil), do: opts
  defp maybe_put_retry_delay(opts, delay), do: Keyword.put(opts, :retry_delay, fn _ -> delay end)

  # The token is only sent to an explicitly configured endpoint, never to the
  # public default, so a missing OVERPASS_API_URL can't leak the credential.
  defp bearer_token(config),
    do: bearer_token(trim_to_nil(config[:api_url]), trim_to_nil(config[:bearer_token]))

  defp bearer_token(nil, _token), do: nil
  defp bearer_token(_api_url, nil), do: nil

  defp bearer_token(api_url, token),
    do: sendable_token(https?(api_url), visible_ascii?(token), token)

  defp sendable_token(false, _valid, _token) do
    Logger.warning("[overpass] bearer token not sent: OVERPASS_API_URL is not https")
    nil
  end

  defp sendable_token(true, false, _token) do
    Logger.warning("[overpass] bearer token not sent: it contains invalid characters")
    nil
  end

  defp sendable_token(true, true, token), do: token

  defp https?(url), do: String.downcase(URI.parse(url).scheme || "") == "https"

  # Mint rejects other characters and echoes the whole header value in its
  # error, which would then be logged, so a malformed token is never sent.
  defp visible_ascii?(token), do: String.match?(token, ~r/\A[\x21-\x7E]+\z/)

  defp trim_to_nil(nil), do: nil
  defp trim_to_nil(value), do: value |> String.trim() |> empty_to_nil()

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp maybe_put_bearer_token(opts, nil), do: opts

  defp maybe_put_bearer_token(opts, token) do
    headers = [{"authorization", "Bearer #{token}"} | opts[:headers]]
    Keyword.put(opts, :headers, headers)
  end

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
