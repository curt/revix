defmodule RevixWeb.PingsLive do
  use RevixWeb, :live_view

  alias Revix.{People, Pings}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.person.role != :owner do
      {:ok,
       socket
       |> put_flash(:error, "You are not authorized to view this page.")
       |> redirect(to: ~p"/")}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Revix.PubSub, "pings")
      end

      pings = Pings.list_recent()

      {:ok,
       socket
       |> assign(:pings, pings)
       |> assign(:people, load_people(pings))
       |> assign(:target_uri, "")
       |> assign(:sending, false)}
    end
  end

  @impl true
  def handle_event("send_ping", %{"target_uri" => target_uri}, socket) do
    scope = socket.assigns.current_scope
    person = scope.person

    uri_fn = fn id -> "#{person.uri}/ping/#{id}" end

    case Pings.send_ping(scope, String.trim(target_uri), uri_fn) do
      {:ok, _ping} ->
        pings = Pings.list_recent()

        {:noreply,
         socket
         |> assign(:pings, pings)
         |> assign(:people, load_people(pings))
         |> assign(:target_uri, "")
         |> put_flash(:info, "Ping sent.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to send ping.")}
    end
  end

  @impl true
  def handle_event("update_target", %{"target_uri" => value}, socket) do
    {:noreply, assign(socket, :target_uri, value)}
  end

  @impl true
  def handle_info(:pings_updated, socket) do
    pings = Pings.list_recent()
    {:noreply, socket |> assign(:pings, pings) |> assign(:people, load_people(pings))}
  end

  attr :person, :map, default: nil
  attr :uri, :string, required: true

  defp person_link(%{person: nil} = assigns) do
    ~H"""
    <span class="font-mono text-xs text-zinc-400" title={@uri}>{@uri}</span>
    """
  end

  defp person_link(assigns) do
    ~H"""
    <a href={@person.url} class="flex items-center gap-2 min-w-0" title={@uri}>
      <div class="avatar shrink-0">
        <div class="w-6 rounded-full">
          <.avatar_image person={@person} alt={person_display_name(@person)} />
        </div>
      </div>
      <span class="truncate text-sm">{person_display_name(@person)}</span>
    </a>
    """
  end

  defp load_people(pings) do
    uris = Enum.flat_map(pings, &[&1.actor_uri, &1.target_uri]) |> Enum.uniq()
    People.get_people_by_uris(uris)
  end

  defp person_display_name(person) do
    person.display_name || person.username || person.id
  end

  defp format_age(%{inserted_at: dt}) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp status_class(:pending), do: "text-yellow-600"
  defp status_class(:delivered), do: "text-green-600"
  defp status_class(:failed), do: "text-red-600"
end
