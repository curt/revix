defmodule Revix.Workers.InboundNoteHelpers do
  alias Revix.Entries
  alias Revix.Entries.Entry

  def known_context?(note) do
    [note["context"], note["inReplyTo"]]
    |> Enum.filter(&is_binary/1)
    |> Enum.any?(fn uri ->
      match?({:ok, %Entry{}}, Entries.get_entry_by_uri(uri))
    end)
  end

  def extract_note_attrs(note, actor_uri) do
    %{
      uri: note["id"],
      url: note["url"] || note["id"],
      author_uri: actor_uri,
      content: note["content"],
      in_reply_to_uri: note["inReplyTo"],
      context: resolve_context(note),
      published_at_utc: parse_datetime(note["published"]),
      modified_at_utc: parse_datetime(note["updated"])
    }
  end

  def extract_locations(note) do
    note["location"]
    |> List.wrap()
    |> Enum.filter(&is_map/1)
  end

  def checkin?(note) do
    length(extract_locations(note)) == 1 and is_binary(note["startTime"])
  end

  def extract_place_attrs(nil), do: nil

  def extract_place_attrs(loc) do
    with uri when is_binary(uri) <- loc["id"],
         name when is_binary(name) <- loc["name"],
         lat when is_number(lat) <- loc["latitude"],
         lon when is_number(lon) <- loc["longitude"] do
      osm_attrs = parse_osm_same_as(loc["sameAs"])

      Map.merge(
        %{
          uri: uri,
          name: name,
          latitude: lat,
          longitude: lon,
          url: loc["url"] || uri,
          altitude: loc["altitude"]
        },
        osm_attrs
      )
    else
      _ -> nil
    end
  end

  @osm_uri_pattern ~r{^https://www\.openstreetmap\.org/(node|way|relation)/(\d+)$}

  defp parse_osm_same_as(nil), do: %{}

  defp parse_osm_same_as(same_as) when is_binary(same_as) do
    case Regex.run(@osm_uri_pattern, same_as, capture: :all_but_first) do
      [type_str, id_str] ->
        %{osm_type: String.to_existing_atom(type_str), osm_id: String.to_integer(id_str)}

      nil ->
        %{}
    end
  end

  def extract_attachments(note) do
    note["attachment"]
    |> List.wrap()
    |> Enum.filter(fn a ->
      is_map(a) and a["type"] in ["Document", "Image"] and is_binary(a["url"])
    end)
  end

  # Resolve the canonical local context for a remote note.
  # Remote actors set context inconsistently (nil, foreign thread URI, or correct
  # checkin URI). We walk up via inReplyTo to find the true local root, overriding
  # whatever the remote actor sent as context.
  defp resolve_context(note) do
    in_reply_to = note["inReplyTo"]

    resolved =
      if is_binary(in_reply_to) do
        Entries.get_entry_context_uri(in_reply_to)
      end

    resolved || note["context"] || in_reply_to
  end

  def parse_datetime(nil), do: nil

  def parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
