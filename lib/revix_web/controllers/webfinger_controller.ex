defmodule RevixWeb.WebfingerController do
  use RevixWeb, :controller

  alias Revix.Webfinger

  action_fallback RevixWeb.FallbackController

  def show(conn, %{"resource" => resource}) do
    with {:ok, {person, canonical_resource}} <-
           Webfinger.get_webfinger(resource, conn.host) do
      aliases = [person_uri(person), person_url(person)] |> Enum.dedup()

      json(conn, %{
        subject: canonical_resource,
        aliases: aliases,
        links: [
          %{
            rel: "self",
            type: "application/activity+json",
            href: person_uri(person)
          }
        ]
      })
    end
  end

  def show(_conn, _) do
    {:error, :bad_request}
  end
end
