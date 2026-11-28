defmodule RevixWeb.CompanionsComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias RevixWeb.CompanionsComponent

  @alice %{
    uri: "https://a.example/people/1",
    display_name: "Alice",
    username: nil,
    avatar_url: nil
  }
  @bob %{uri: "https://b.example/people/2", display_name: nil, username: "bob", avatar_url: nil}

  defp render_section(assigns) do
    assigns = Map.merge(%{companions: [], companion_query: "", companion_results: []}, assigns)

    render_component(&CompanionsComponent.companions_section/1, assigns)
    |> LazyHTML.from_fragment()
  end

  defp attr(doc, selector, name) do
    doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  end

  test "the search box has a visible label" do
    doc = render_section(%{})
    [input_id] = attr(doc, "input[name=companion_query]", "id")

    assert doc |> LazyHTML.query("label[for='#{input_id}']") |> LazyHTML.text() =~
             "Search people"
  end

  test "the picker is wired to the CompanionPicker hook" do
    doc = render_section(%{})
    assert attr(doc, "[phx-hook=CompanionPicker]", "id") != []

    assert attr(doc, "[phx-hook=CompanionPicker] input[data-companion-search]", "name") == [
             "companion_query"
           ]
  end

  test "each result is a focusable button that adds the companion without submitting" do
    doc = render_section(%{companion_results: [@alice, @bob]})
    buttons = LazyHTML.query(doc, "button[data-companion-result]")

    assert LazyHTML.attribute(buttons, "type") == ["button", "button"]
    assert LazyHTML.attribute(buttons, "phx-click") == ["add_companion", "add_companion"]
    assert LazyHTML.attribute(buttons, "phx-value-uri") == [@alice.uri, @bob.uri]
    assert LazyHTML.text(buttons) =~ "Alice"
    assert LazyHTML.text(buttons) =~ "bob"
  end

  test "no element other than a button handles a result click" do
    doc = render_section(%{companion_results: [@alice]})
    assert attr(doc, "li[phx-click]", "phx-click") == []
  end

  test "each chip's remove button names the companion" do
    doc = render_section(%{companions: [@alice, @bob]})

    assert attr(doc, "button[phx-click=remove_companion]", "aria-label") ==
             ["Remove Alice", "Remove bob"]
  end

  test "says changes save right away when they do, as on edit pages" do
    doc = render_section(%{saves_immediately: true})

    assert doc |> LazyHTML.query("[data-saves-immediately]") |> LazyHTML.text() =~
             "save right away"
  end

  test "says nothing about saving on create pages, where Save applies" do
    assert render_section(%{}) |> LazyHTML.query("[data-saves-immediately]") |> Enum.count() == 0
  end
end
