defmodule RevixWeb.CheckinSettingsLive do
  use RevixWeb, :live_view

  alias Revix.People
  alias Revix.People.Person
  alias Revix.People.Scope

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :form, preferences_form(current_person(socket)))}
  end

  @impl true
  def handle_event("save", %{"checkin" => params}, socket) do
    person = current_person(socket)

    case People.update_checkin_preferences(person, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Checkin settings updated.")
         |> assign(:current_scope, Scope.for_person(updated))
         |> assign(:form, preferences_form(updated))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :checkin))}
    end
  end

  defp current_person(socket), do: socket.assigns.current_scope.person

  defp preferences_form(%Person{} = person) do
    person
    |> Person.checkin_preferences_changeset(%{})
    |> to_form(as: :checkin)
  end
end
