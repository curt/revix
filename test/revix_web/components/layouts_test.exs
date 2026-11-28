defmodule RevixWeb.LayoutsTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Revix.People.Person
  alias Revix.People.Scope

  defp render_app(scope) do
    assigns = %{scope: scope, site: %Revix.Sites.Site{title: "Trail Log"}}

    ~H"""
    <RevixWeb.Layouts.app flash={%{}} current_scope={@scope} site={@site}>page</RevixWeb.Layouts.app>
    """
    |> rendered_to_string()
    |> LazyHTML.from_fragment()
  end

  defp scope(attrs),
    do: Scope.for_person(struct(%Person{role: :user, uri: "u", email: "ada@example.com"}, attrs))

  test "the menu button has an accessible name" do
    doc = render_app(nil)

    assert doc |> LazyHTML.query("nav [role=button]") |> LazyHTML.attribute("aria-label") == [
             "Menu"
           ]
  end

  test "the site title links home" do
    doc = render_app(nil)
    assert doc |> LazyHTML.query("nav a[href='/']") |> LazyHTML.text() =~ "Trail Log"
  end

  test "the header names you by display name, never your email" do
    html = render_app(scope(display_name: "Ada", username: "ada")) |> LazyHTML.to_html()
    assert html =~ "Ada"
    refute html =~ "ada@example.com"
  end

  test "the header falls back to @username without a display name" do
    html = render_app(scope(display_name: nil, username: "ada")) |> LazyHTML.to_html()
    assert html =~ "@ada"
    refute html =~ "ada@example.com"
  end

  test "the header shows no name, and still no email, without a display name or username" do
    html = render_app(scope(display_name: nil, username: nil)) |> LazyHTML.to_html()
    refute html =~ "ada@example.com"
  end
end
