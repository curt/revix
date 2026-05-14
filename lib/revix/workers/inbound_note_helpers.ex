defmodule Revix.Workers.InboundNoteHelpers do
  alias Revix.Entries
  alias Revix.Entries.Entry

  def local_context?(note) do
    [note["context"], note["inReplyTo"]]
    |> Enum.filter(&is_binary/1)
    |> Enum.any?(fn uri ->
      match?({:ok, %Entry{origin: :local}}, Entries.get_entry_by_uri(uri))
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
      published_at_utc: parse_datetime(note["published"])
    }
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
