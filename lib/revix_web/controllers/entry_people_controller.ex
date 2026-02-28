defmodule RevixWeb.EntryPeopleController do
  use RevixWeb, :controller

  alias Revix.EntryPeople

  def create(conn, %{"entry_uri" => entry_uri, "person_uri" => person_uri}) do
    scope = conn.assigns.current_scope

    case EntryPeople.add_companion(scope, entry_uri, person_uri) do
      {:ok, _entry_person} ->
        json(conn, companions_response(entry_uri))

      {:error, :self_companion} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You cannot add yourself as a companion"})

      {:error, :not_authorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You can only manage companions for your own checkins"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Could not add companion"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Missing required parameters"})
  end

  def delete(conn, %{"entry_uri" => entry_uri, "person_uri" => person_uri}) do
    scope = conn.assigns.current_scope

    case EntryPeople.remove_companion(scope, entry_uri, person_uri) do
      {:ok, _entry_person} ->
        json(conn, companions_response(entry_uri))

      {:error, :not_found} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Companion not found"})

      {:error, :not_authorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You can only manage companions for your own checkins"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Could not remove companion"})
    end
  end

  def delete(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Missing required parameters"})
  end

  defp companions_response(entry_uri) do
    companions = EntryPeople.get_companions_for_entry(entry_uri)
    count = length(companions)

    companion_data =
      companions
      |> Enum.take(5)
      |> Enum.filter(& &1.person)
      |> Enum.map(fn ep ->
        %{
          uri: ep.person.uri,
          display_name: ep.person.display_name,
          username: ep.person.username,
          avatar_url: Revix.Uploaders.Avatar.url({ep.person.avatar, ep.person}, :thumb)
        }
      end)

    %{companions: companion_data, count: count, total: count}
  end
end
