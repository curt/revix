defmodule Revix.Workers.ProcessInboundUpdateNoteWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.EntryPlaces
  alias Revix.Follows
  alias Revix.Media
  alias Revix.Places
  alias Revix.Workers.InboundNoteHelpers

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => _person_id}}) do
    note = activity["object"]
    actor_uri = activity["actor"]

    with true <- is_map(note),
         note_uri when is_binary(note_uri) <- note["id"],
         actor_uri when is_binary(actor_uri) <- actor_uri do
      if InboundNoteHelpers.known_context?(note) or Follows.followed_by_any_local?(actor_uri) do
        attrs = InboundNoteHelpers.extract_note_attrs(note, actor_uri)

        case Entries.update_inbound_note(note_uri, actor_uri, attrs) do
          {:ok, entry} ->
            import_locations(entry, InboundNoteHelpers.extract_locations(note))
            import_attachments(entry, InboundNoteHelpers.extract_attachments(note))
            :ok

          {:error, :not_remote} ->
            :ok

          {:error, :not_owner} ->
            :ok

          {:error, reason} ->
            {:error, reason}
        end
      else
        :ok
      end
    else
      _ -> {:error, :invalid_activity}
    end
  end

  def perform(%Oban.Job{}), do: {:error, :invalid_activity}

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
end
