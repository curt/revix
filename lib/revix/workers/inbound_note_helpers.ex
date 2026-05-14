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
      context: note["context"],
      published_at_utc: parse_datetime(note["published"])
    }
  end

  def parse_datetime(nil), do: nil

  def parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
