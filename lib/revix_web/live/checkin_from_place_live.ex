defmodule RevixWeb.CheckinFromPlaceLive do
  use RevixWeb, :live_view

  alias RevixWeb.Live.EntryForm

  alias Revix.People.Scope

  import RevixWeb.Live.EntryHelpers

  alias Revix.Entries
  alias Revix.Places
  alias RevixWeb.CanonicalRoutes

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket.assigns.current_scope
    |> Scope.owner?()
    |> mount_for_owner(id, socket)
  end

  # Owner-only, checked here rather than in the router on purpose, so place-first
  # check-ins can later open up to other people.
  defp mount_for_owner(false, _id, socket) do
    {:ok,
     socket
     |> put_flash(:error, "You are not authorized to check in from a place page.")
     |> redirect(to: ~p"/checkins/new")}
  end

  defp mount_for_owner(true, id, socket) do
    id
    |> Places.get_local_place()
    |> mount_for_place(socket)
  end

  defp mount_for_place({:ok, place}, socket) do
    scope = socket.assigns.current_scope

    socket =
      socket
      |> assign(:place, place)
      |> assign(:checkin_form, Entries.change_checkin(scope.role) |> to_form(as: :checkin))
      |> assign(:companions, [])
      |> assign(:companion_query, "")
      |> assign(:companion_results, [])
      |> assign(:timezones, Tzdata.zone_list() |> Enum.sort())
      |> assign(:can_edit_datetime, Scope.owner?(scope))
      |> assign(:upload_captions, %{})
      |> assign(:upload_order, [])
      |> assign(:show_publish_modal, false)
      |> EntryForm.attach_companions(:draft)
      |> EntryForm.attach_photos(:new)
      |> EntryForm.attach_dialogs()
      |> assign(:pending_publish_params, nil)
      |> allow_upload(:images,
        accept: ~w(.jpg .jpeg .gif .png .webp),
        max_entries: 10,
        max_file_size: 20_000_000
      )

    {:ok, socket}
  end

  defp mount_for_place({:error, :not_found}, socket) do
    {:ok,
     socket
     |> put_flash(:error, "Place not found.")
     |> redirect(to: ~p"/places")}
  end

  @impl true
  def handle_event("set_defaults", %{"local_datetime" => dt, "timezone" => tz}, socket) do
    role = socket.assigns.current_scope.role

    form =
      Entries.change_checkin(role, %{"starts_at_local" => dt, "starts_tz" => tz})
      |> to_form(as: :checkin)

    {:noreply, assign(socket, :checkin_form, form)}
  end

  def handle_event("validate", params, socket) do
    role = socket.assigns.current_scope.role

    checkin_form =
      Entries.change_checkin(role, params["checkin"] || %{})
      |> Map.put(:action, :validate)
      |> to_form(as: :checkin)

    {:noreply, assign(socket, :checkin_form, checkin_form)}
  end

  def handle_event(
        "update_caption",
        %{"_target" => [_, ref], "photo_caption" => captions_map},
        socket
      ) do
    value = Map.get(captions_map, ref, "")

    captions =
      Map.update(
        socket.assigns.upload_captions,
        ref,
        %{caption: value, alt: ""},
        &Map.put(&1, :caption, value)
      )

    {:noreply, assign(socket, :upload_captions, captions)}
  end

  def handle_event(
        "submit",
        %{"checkin" => checkin_params, "action" => "publish"},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:show_publish_modal, true)
     |> assign(:pending_publish_params, checkin_params)}
  end

  def handle_event("submit", %{"checkin" => checkin_params, "action" => "view"}, socket) do
    do_create_checkin(socket, checkin_params, :view)
  end

  def handle_event("submit", %{"checkin" => checkin_params}, socket) do
    do_create_checkin(socket, checkin_params, :draft)
  end

  def handle_event("confirm_publish", _params, socket) do
    do_create_checkin(socket, socket.assigns.pending_publish_params, :publish)
  end

  defp do_create_checkin(socket, checkin_params, mode) do
    scope = socket.assigns.current_scope
    place = socket.assigns.place
    companion_uris = Enum.map(socket.assigns.companions, & &1.uri)

    case Entries.create_local_checkin_with_companions(
           scope,
           place,
           checkin_params,
           &CanonicalRoutes.checkin_uri/1,
           &CanonicalRoutes.checkin_url/2,
           companion_uris,
           enqueue_delivery: false,
           mode: entries_mode(mode)
         ) do
      {:ok, checkin} ->
        consume_uploads(socket, checkin.id, scope.person.uri)
        if mode == :publish, do: Entries.enqueue_delivery(checkin, "Create")

        flash = if mode == :publish, do: "Checkin published.", else: "Draft saved."

        {:noreply,
         socket
         |> put_flash(:info, flash)
         |> redirect(to: save_destination(mode, checkin))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:show_publish_modal, false)
         |> assign(checkin_form: Map.put(changeset, :action, :insert) |> to_form(as: :checkin))}
    end
  end

  defp save_destination(:draft, checkin), do: ~p"/checkins/#{checkin.id}/edit"
  defp save_destination(_mode, checkin), do: CanonicalRoutes.checkin_path(checkin)

  # View saves a draft, then shows it.
  defp entries_mode(:view), do: :draft
  defp entries_mode(mode), do: mode
end
