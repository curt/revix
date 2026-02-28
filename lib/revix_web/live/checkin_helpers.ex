defmodule RevixWeb.Live.CheckinHelpers do
  alias Revix.Media
  alias Revix.People
  alias RevixWeb.CanonicalRoutes

  def normalize_person(p) do
    %{
      uri: p.uri,
      display_name: p.display_name,
      username: p.username,
      avatar_url: CanonicalRoutes.avatar_url(p)
    }
  end

  def search_companions("", _exclude_uri), do: []

  def search_companions(query, exclude_uri) do
    People.search_people(query, exclude_uri) |> Enum.map(&normalize_person/1)
  end

  def consume_uploads(socket, entry_id, author_uri, start_position \\ 0) do
    upload_order = socket.assigns.upload_order
    upload_captions = socket.assigns.upload_captions
    entries = socket.assigns.uploads.images.entries

    position_map = build_position_map(entries, upload_order, start_position)

    Phoenix.LiveView.consume_uploaded_entries(socket, :images, fn %{path: temp_path}, entry ->
      position = Map.get(position_map, entry.ref, start_position)
      caption = get_in(upload_captions, [entry.ref, :caption])
      alt = get_in(upload_captions, [entry.ref, :alt])

      plug_upload = %Plug.Upload{
        path: temp_path,
        filename: entry.client_name,
        content_type: entry.client_type
      }

      case Media.create_image(%{
             file: plug_upload,
             author_uri: author_uri,
             content_type: entry.client_type,
             original_filename: entry.client_name
           }) do
        {:ok, image} ->
          Media.attach_image_to_entry(entry_id, image.id, position)

          meta =
            %{}
            |> then(fn m ->
              if caption && caption != "", do: Map.put(m, :caption, caption), else: m
            end)
            |> then(fn m -> if alt && alt != "", do: Map.put(m, :alt, alt), else: m end)

          if meta != %{}, do: Media.update_image(image, meta)

          {:ok, image}

        _ ->
          {:ok, :skipped}
      end
    end)
  end

  defp build_position_map(entries, [], start_position) do
    entries |> Enum.with_index(start_position) |> Map.new(fn {e, i} -> {e.ref, i} end)
  end

  defp build_position_map(entries, upload_order, start_position) do
    entries
    |> Enum.reduce({%{}, start_position + length(upload_order)}, fn entry, {map, fallback} ->
      case Enum.find_index(upload_order, &(&1 == entry.ref)) do
        nil -> {Map.put(map, entry.ref, fallback), fallback + 1}
        pos -> {Map.put(map, entry.ref, start_position + pos), fallback}
      end
    end)
    |> elem(0)
  end
end
