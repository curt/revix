defmodule RevixWeb.NoteController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.Repo

  action_fallback RevixWeb.FallbackController

  def show(conn, %{"id" => id}) do
    with {:ok, note} <- Entries.get_comment_with_author(id) do
      show_by_format(conn, note, get_format(conn))
    end
  end

  defp show_by_format(conn, %{tombstoned_at: ts} = note, "activity") when not is_nil(ts) do
    activity(conn, to_tombstone_activity(note), status: 410)
  end

  defp show_by_format(conn, note, "activity") do
    activity(conn, to_note_activity(note))
  end

  defp show_by_format(conn, note, _format) do
    with {:ok, checkin} <- get_context_checkin(note) do
      checkin = Repo.preload(checkin, :place)
      redirect(conn, to: "#{checkin_path(checkin)}#comment-#{note.id}")
    end
  end

  def create(conn, %{"note" => %{"in_reply_to_uri" => in_reply_to_uri} = note_params}) do
    scope = conn.assigns.current_scope

    with {:ok, parent} <- Entries.get_entry_by_uri(in_reply_to_uri),
         {:ok, checkin} <- get_context_checkin(parent) do
      checkin = Repo.preload(checkin, :place)
      path = checkin_path(checkin)

      create_fn =
        case parent.type do
          :note ->
            fn -> Entries.create_reply(scope, parent, note_params, &note_uri/1, &note_url/1) end

          _ ->
            fn ->
              Entries.create_comment(scope, checkin, note_params, &note_uri/1, &note_url/1)
            end
        end

      case create_fn.() do
        {:ok, note} ->
          conn
          |> put_flash(:info, "Comment added.")
          |> redirect(to: "#{path}#comment-#{note.id}")

        {:error, changeset} ->
          errors =
            Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
              Enum.reduce(opts, msg, fn {key, value}, acc ->
                String.replace(acc, "%{#{key}}", to_string(value))
              end)
            end)

          error_msg = errors |> Map.values() |> List.flatten() |> Enum.join(", ")

          conn
          |> put_flash(:error, "Could not save comment: #{error_msg}")
          |> redirect(to: path)
      end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Missing required parameters"})
  end

  def update(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope

    with {:ok, note} <- Entries.get_comment(id),
         :ok <- authorize_edit(note, scope) do
      case Entries.update_comment(note, Map.take(params["note"] || %{}, ["content"])) do
        {:ok, updated} ->
          json(conn, %{content_html: updated.content_html, content: updated.content})

        {:error, changeset} ->
          errors =
            Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
              Enum.reduce(opts, msg, fn {key, value}, acc ->
                String.replace(acc, "%{#{key}}", to_string(value))
              end)
            end)

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: errors})
      end
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    with {:ok, note} <- Entries.get_comment(id),
         :ok <- authorize_edit(note, scope) do
      {:ok, _} = Entries.delete_comment(note)
      json(conn, %{ok: true})
    end
  end

  defp get_context_checkin(%{type: :note} = note), do: walk_to_checkin(note.in_reply_to_uri)
  defp get_context_checkin(checkin), do: {:ok, checkin}

  defp walk_to_checkin(nil), do: {:error, :not_found}

  defp walk_to_checkin(uri) do
    case Entries.get_entry_by_uri(uri) do
      {:ok, %Entry{type: :checkin} = checkin} -> {:ok, checkin}
      {:ok, %Entry{in_reply_to_uri: parent_uri}} -> walk_to_checkin(parent_uri)
      other -> other
    end
  end

  defp authorize_edit(note, scope) do
    if note.author_uri == scope.person.uri, do: :ok, else: {:error, :unauthorized}
  end
end
