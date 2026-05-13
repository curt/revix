defmodule RevixWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  defp render_map(attrs \\ []) do
    assigns = Map.new(attrs)

    rendered_to_string(~H"""
    <RevixWeb.CoreComponents.map class={assigns[:class]} />
    """)
  end

  describe "map/1" do
    test "renders a div with id=map" do
      assert render_map() =~ ~s(id="map")
    end

    test "includes rounded class by default" do
      assert render_map() =~ "rounded"
    end

    test "merges additional classes" do
      html = render_map(class: "h-64")
      assert html =~ "rounded"
      assert html =~ "h-64"
    end
  end
end
