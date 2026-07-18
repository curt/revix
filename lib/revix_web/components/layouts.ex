defmodule RevixWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use RevixWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8 bg-base-100 shadow-sm">
      <nav class="navbar-start">
        <div class="dropdown">
          <div tabindex="0" role="button" class="btn btn-ghost btn-circle">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 6h16M4 12h16M4 18h16"
              />
            </svg>
          </div>
          <ul
            tabindex="-1"
            class="menu dropdown-content bg-base-200 rounded-box z-1 mt-3 w-52 p-2 shadow"
          >
            <li><.link href={~p"/"}>Home</.link></li>
            <li>
              <.link href={~p"/places"}>Places</.link>
              <%= if @current_scope && @current_scope.person.role == :owner do %>
                <ul>
                  <li><.link href={~p"/places/new"}>New Place</.link></li>
                </ul>
              <% end %>
            </li>
            <li>
              <.link href={~p"/posts"}>Posts</.link>
              <%= if @current_scope && @current_scope.person.role == :owner do %>
                <ul>
                  <li><.link href={~p"/posts/new"}>New Post</.link></li>
                </ul>
              <% end %>
            </li>
            <li>
              <.link href={~p"/checkins"}>Checkins</.link>
              <%= if @current_scope do %>
                <ul>
                  <li><.link href={~p"/checkins/new"}>New Checkin</.link></li>
                </ul>
              <% end %>
            </li>
            <%= if @current_scope do %>
              <li>
                <.link href={~p"/people/settings"}>Settings</.link>
              </li>
              <li>
                <.link href={~p"/following"}>Following</.link>
              </li>
              <%= if @current_scope.person.role == :owner do %>
                <li>
                  <.link href={~p"/pings"}>Pings</.link>
                </li>
              <% end %>
              <li>
                <.link href={~p"/people/signout"} method="delete">Sign out</.link>
              </li>
            <% else %>
              <li>
                <.link href={~p"/people/signin"}>Sign in</.link>
              </li>
            <% end %>
            <li><.link href={~p"/credits"}>Credits</.link></li>
          </ul>
        </div>
        <span class="font-semibold pl-2">Revix</span>
      </nav>
      <div class="navbar-end">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <%= if @current_scope do %>
            <li class="hidden sm:block">
              {@current_scope.person.email}
            </li>
            <li>
              <div class="avatar">
                <div class="w-8 rounded-full">
                  <img
                    src={
                      Revix.Uploaders.Avatar.url(
                        {@current_scope.person.avatar, @current_scope.person},
                        :thumb
                      )
                    }
                    alt={@current_scope.person.display_name || @current_scope.person.username || ""}
                  />
                </div>
              </div>
            </li>
          <% end %>
          <li>
            <.theme_toggle />
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-4 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  defp s3_asset_host, do: Application.get_env(:waffle, :asset_host)

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
