defmodule RevixWeb.NotificationSettingsLive do
  use RevixWeb, :live_view

  alias Revix.Notifications
  alias Revix.People.Person
  alias Revix.People.Scope

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :form, schedule_form(current_person(socket)))}
  end

  @impl true
  def handle_event("save", %{"notification" => %{"notification_schedule" => value}}, socket) do
    person = current_person(socket)

    case Notifications.set_schedule(person, String.to_existing_atom(value)) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Notification frequency updated.")
         |> assign(:current_scope, Scope.for_person(updated))
         |> assign(:form, schedule_form(updated))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :notification))}
    end
  end

  defp current_person(socket), do: socket.assigns.current_scope.person

  defp schedule_form(%Person{} = person) do
    person
    |> Person.notification_changeset(%{})
    |> to_form(as: :notification)
  end
end
