defmodule Revix.Federation.Actors do
  @moduledoc """
  Remote ActivityPub actors stored as local `Person` records: fetching an
  actor from its server, keeping it fresh, upserting it, and downloading its
  avatar.
  """
  import Ecto.Query, warn: false
  alias Revix.Federation.SafeHttp
  alias Revix.Repo
  alias Revix.People.Person

  def get_or_fetch_person_by_uri(uri, opts \\ []) when is_binary(uri) do
    force = Keyword.get(opts, :force_refresh, false)
    refresh_hours = Application.get_env(:revix, :federation)[:key_refresh_hours] || 24
    stale_cutoff = DateTime.add(DateTime.utc_now(), -refresh_hours * 3600, :second)

    uri
    |> Revix.People.get_person_by_uri()
    |> maybe_refresh_person(uri, force, stale_cutoff)
  end

  defp maybe_refresh_person({:ok, %Person{origin: :local} = person}, _uri, _force, _stale_cutoff),
    do: {:ok, person}

  defp maybe_refresh_person({:ok, person}, _uri, false, stale_cutoff) do
    if DateTime.before?(person.updated_at, stale_cutoff),
      do: refresh_remote_person(person.uri),
      else: {:ok, person}
  end

  defp maybe_refresh_person({:ok, person}, _uri, true, _stale_cutoff),
    do: refresh_remote_person(person.uri)

  defp maybe_refresh_person({:error, :not_found}, uri, _force, _stale_cutoff),
    do: refresh_remote_person(uri)

  defp refresh_remote_person(actor_uri) do
    with {:ok, actor} <- Revix.Federation.fetch_actor(actor_uri),
         {:ok, canonical_uri} <- same_origin_id(actor_uri, actor["id"]) do
      attrs = %{
        uri: canonical_uri,
        url: actor["url"],
        username: actor["preferredUsername"],
        display_name: actor["name"],
        public_key: extract_public_key(actor),
        icon_url: extract_icon_url(actor)
      }

      upsert_remote_person(attrs)
    end
  end

  defp same_origin_id(actor_uri, nil), do: {:ok, actor_uri}

  defp same_origin_id(actor_uri, id) when is_binary(id) do
    actor_uri
    |> Revix.Federation.Origin.same?(id)
    |> canonical_id(id)
  end

  defp canonical_id(true, id), do: {:ok, id}
  defp canonical_id(false, _id), do: {:error, :actor_id_origin_mismatch}

  defp extract_public_key(%{"publicKey" => %{"publicKeyPem" => pem}}), do: pem
  defp extract_public_key(_), do: nil

  defp extract_icon_url(%{"icon" => %{"url" => url}}) when is_binary(url), do: url
  defp extract_icon_url(%{"icon" => url}) when is_binary(url), do: url
  defp extract_icon_url(_), do: nil

  def upsert_remote_person(attrs) when is_map(attrs) do
    id = Revix.Ecto.Base58Id.autogenerate()

    result =
      %Person{}
      |> Person.remote_changeset(Map.put_new(attrs, :id, id))
      |> Repo.insert(
        on_conflict: {:replace, [:display_name, :username, :public_key, :url, :updated_at]},
        conflict_target: :uri
      )

    case result do
      {:ok, person} ->
        maybe_fetch_remote_avatar(person, attrs[:icon_url])
        {:ok, person}

      {:error, _} ->
        Revix.People.get_person_by_uri(attrs.uri)
    end
  rescue
    Ecto.StaleEntryError -> Revix.People.get_person_by_uri(attrs.uri)
  end

  defp maybe_fetch_remote_avatar(_person, nil), do: :ok

  defp maybe_fetch_remote_avatar(person, icon_url) do
    with {:ok, %{status: 200, body: body}} <-
           SafeHttp.get(icon_url, retry: false, decode_body: false, stub: :federation_req_plug),
         type when type in [:jpeg, :gif, :png] <- ExImageInfo.seems?(body),
         ext = Atom.to_string(if type == :jpeg, do: :jpg, else: type),
         upload = %{filename: "avatar.#{ext}", binary: body},
         {:ok, _} <-
           person
           |> Person.avatar_changeset(%{avatar: upload})
           |> Repo.update() do
      :ok
    else
      _ -> :ok
    end
  end
end
