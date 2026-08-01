defmodule RevixWeb.SiteSettingsLive do
  use RevixWeb, :live_view

  alias Revix.Sites
  alias Revix.Sites.Site
  alias RevixWeb.CanonicalRoutes

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.role != :owner do
      {:ok,
       socket
       |> put_flash(:error, "You are not authorized to edit site settings.")
       |> redirect(to: ~p"/")}
    else
      site = socket.assigns.site

      {:ok,
       socket
       |> assign(:endpoint, CanonicalRoutes.home_url())
       |> assign(:form, site_form(site))
       |> assign(:description_html, Sites.description_html(site))}
    end
  end

  @impl true
  def handle_event("validate", %{"site" => params}, socket) do
    form =
      socket.assigns.site
      |> Site.changeset(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :site)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:description_html, preview_html(params["description"]))}
  end

  def handle_event("save", %{"site" => params}, socket) do
    case Sites.update_site(socket.assigns.endpoint, params) do
      {:ok, site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Site settings updated.")
         |> assign(:site, site)
         |> assign(:form, site_form(site))
         |> assign(:description_html, Sites.description_html(site))}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :form, changeset |> Map.put(:action, :update) |> to_form(as: :site))}
    end
  end

  defp site_form(%Site{} = site) do
    site
    |> Site.changeset(%{})
    |> to_form(as: :site)
  end

  defp preview_html(nil), do: nil
  defp preview_html(description), do: Sites.description_html(%Site{description: description})
end
