defmodule RevixWeb.CompanionsComponent do
  use RevixWeb, :html

  @doc """
  Renders the companions search/add/remove section.

  Expects companions to be a list of maps with keys:
    %{uri: string, display_name: string | nil, username: string | nil, avatar_url: string | nil}
  """
  attr :companions, :list, required: true
  attr :companion_query, :string, required: true
  attr :companion_results, :list, required: true

  def companions_section(assigns) do
    ~H"""
    <div>
      <h2 class="text-lg font-semibold mb-3">Companions</h2>
      <p class="text-sm text-base-content/70 mb-3">Who was with you?</p>

      <div class="relative">
        <input
          type="text"
          name="companion_query"
          value={@companion_query}
          placeholder="Search by name or URI..."
          phx-change="search_companions"
          phx-debounce="300"
          autocomplete="off"
          class="input input-bordered w-full"
        />
        <ul
          :if={@companion_results != []}
          class="absolute z-10 w-full bg-base-100 border border-base-300 rounded shadow-lg mt-1"
        >
          <li
            :for={person <- @companion_results}
            class="flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-base-200 text-sm"
            phx-click="add_companion"
            phx-value-uri={person.uri}
          >
            <img
              :if={person.avatar_url}
              src={person.avatar_url}
              class="w-6 h-6 rounded-full object-cover"
              alt=""
            />
            <.icon
              :if={!person.avatar_url}
              name="hero-user-circle"
              class="w-6 h-6 text-base-content/40"
            />
            <span>{person.display_name || person.username || person.uri}</span>
          </li>
        </ul>
      </div>

      <div :if={@companions != []} class="flex flex-wrap gap-2 mt-3">
        <div :for={companion <- @companions} class="badge badge-lg gap-1">
          <img
            :if={companion.avatar_url}
            src={companion.avatar_url}
            class="w-4 h-4 rounded-full object-cover"
            alt=""
          />
          <.icon
            :if={!companion.avatar_url}
            name="hero-user-circle"
            class="w-4 h-4 text-base-content/40"
          />
          <span>{companion.display_name || companion.username || companion.uri}</span>
          <button
            type="button"
            phx-click="remove_companion"
            phx-value-uri={companion.uri}
            aria-label="Remove companion"
            class="ml-1 hover:text-error"
          >
            &times;
          </button>
        </div>
      </div>
    </div>
    """
  end
end
