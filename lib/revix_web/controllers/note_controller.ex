defmodule RevixWeb.NoteController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.Repo

  action_fallback RevixWeb.FallbackController

  def show(conn, %{"id" => id}) do
    with {:ok, note} <- Entries.get_comment(id),
         {:ok, checkin} <- Entries.get_entry_by_uri(note.context) do
      checkin = Repo.preload(checkin, :place)
      path = checkin_path(checkin)
      redirect(conn, to: "#{path}#comment-#{id}")
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

  # For a note (comment or reply), context always holds the root checkin URI regardless
  # of reply depth. For a checkin parent, return it directly.
  defp get_context_checkin(%{type: :note, context: context_uri}),
    do: Entries.get_entry_by_uri(context_uri)

  defp get_context_checkin(checkin), do: {:ok, checkin}

  defp authorize_edit(note, scope) do
    if note.author_uri == scope.person.uri, do: :ok, else: {:error, :unauthorized}
  end
end
