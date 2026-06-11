defmodule Revix.Workers.ProcessInboundCreateNoteWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.EntryPlaces
  alias Revix.Follows
  alias Revix.Media
  alias Revix.Places
  alias Revix.Workers.InboundNoteHelpers
  alias Revix.Workers.LocalUriResolver

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => _person_id}}) do
    note = activity["object"]
    actor_uri = activity["actor"]

    with true <- is_map(note),
         note_uri when is_binary(note_uri) <- note["id"],
         actor_uri when is_binary(actor_uri) <- actor_uri do
      note = normalize_local_uris(note)

      # Accepts if the note replies to a local entry OR the actor is followed by a local user.
      if InboundNoteHelpers.local_context?(note) or Follows.followed_by_any_local?(actor_uri) do
        persist_and_broadcast(note, actor_uri)
      else
        :ok
      end
    else
      _ -> {:error, :invalid_activity}
    end
  end

  defp persist_and_broadcast(note, actor_uri) do
    attrs = InboundNoteHelpers.extract_note_attrs(note, actor_uri)
    locations = InboundNoteHelpers.extract_locations(note)

    with {create_fn, resolved_attrs} <- resolve_entry_type(note, attrs, locations),
         {:ok, entry} <- create_fn.(resolved_attrs) do
      import_locations(entry, locations)
      import_attachments(entry, InboundNoteHelpers.extract_attachments(note))
      broadcast_note(entry)
      :ok
    else
      {:error, %Ecto.Changeset{errors: [{:uri, {"has already been taken", _}} | _]}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_entry_type(note, attrs, [loc]) do
    start_time = note["startTime"]

    if is_binary(start_time) do
      place_attrs = InboundNoteHelpers.extract_place_attrs(loc)
      starts_at = InboundNoteHelpers.parse_datetime(start_time)

      case place_attrs && Places.upsert_remote_place(place_attrs) do
        {:ok, place} ->
          checkin_attrs = Map.merge(attrs, %{place_uri: place.uri, starts_at_utc: starts_at})
          {&Entries.create_inbound_checkin/1, checkin_attrs}

        _ ->
          {&Entries.create_inbound_note/1, attrs}
      end
    else
      {&Entries.create_inbound_note/1, attrs}
    end
  end

  defp resolve_entry_type(_note, attrs, _locations) do
    {&Entries.create_inbound_note/1, attrs}
  end

  defp import_locations(%Entry{type: :checkin}, _locations), do: :ok

  defp import_locations(%Entry{} = entry, locations) do
    Enum.each(locations, fn loc ->
      with place_attrs when not is_nil(place_attrs) <-
             InboundNoteHelpers.extract_place_attrs(loc),
           {:ok, place} <- Places.upsert_remote_place(place_attrs) do
        EntryPlaces.add_place(entry.uri, place.uri)
      else
        _ -> :ok
      end
    end)
  end

  defp import_attachments(%Entry{} = entry, attachments) do
    req_plug = Application.get_env(:revix, :inbound_attachment_req_plug)

    attachments
    |> Enum.with_index()
    |> Enum.each(fn {att, position} ->
      with {:ok, %{status: 200, body: body}} <-
             Req.get(att["url"], retry: false, decode_body: false, plug: req_plug),
           type when type in [:jpeg, :gif, :png, :webp] <- ExImageInfo.seems?(body),
           ext = if(type == :jpeg, do: "jpg", else: to_string(type)),
           mime = if(type == :jpeg, do: "image/jpeg", else: "image/#{type}"),
           upload = %{filename: "attachment.#{ext}", binary: body},
           {:ok, image} <-
             Media.create_image(%{
               file: upload,
               author_uri: entry.author_uri,
               content_type: mime,
               alt: att["name"],
               caption: att["summary"]
             }) do
        Media.attach_image_to_entry(entry.id, image.id, position)
      else
        _ -> :ok
      end
    end)
  end

  defp broadcast_note(%Entry{context: context_uri} = note) when is_binary(context_uri) do
    Phoenix.PubSub.broadcast(Revix.PubSub, "context:#{context_uri}", {:comment_created, note})
    Phoenix.PubSub.broadcast(Revix.PubSub, "feed", {:comment_created, note})
  end

  defp broadcast_note(_), do: :ok

  defp normalize_local_uris(note) do
    note
    |> Map.update("inReplyTo", nil, &LocalUriResolver.resolve/1)
    |> Map.update("context", nil, &LocalUriResolver.resolve/1)
  end
end
