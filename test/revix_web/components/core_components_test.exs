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

  describe "confirm_dialog/1" do
    defp render_dialog(attrs \\ []) do
      assigns =
        Map.merge(
          %{
            id: "delete-thing",
            show: true,
            title: "Delete this thing?",
            on_cancel: "cancel_delete",
            on_confirm: "confirm_delete",
            confirm_label: "Delete",
            confirm_class: "btn-error"
          },
          Map.new(attrs)
        )

      rendered_to_string(~H"""
      <RevixWeb.CoreComponents.confirm_dialog
        id={@id}
        show={@show}
        title={@title}
        on_cancel={@on_cancel}
        on_confirm={@on_confirm}
        confirm_label={@confirm_label}
        confirm_class={@confirm_class}
      >
        <p class="py-4">It goes away for good.</p>
      </RevixWeb.CoreComponents.confirm_dialog>
      """)
      |> LazyHTML.from_fragment()
    end

    defp attr_of(doc, selector, name),
      do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

    test "renders nothing when not shown" do
      assert render_dialog(show: false) |> LazyHTML.query("dialog") |> Enum.count() == 0
    end

    test "is opened as a modal by the ConfirmDialog hook, not by the open attribute" do
      doc = render_dialog()

      assert attr_of(doc, "dialog#delete-thing", "phx-hook") == ["ConfirmDialog"]
      assert attr_of(doc, "dialog#delete-thing", "open") == []
    end

    test "keeps LiveView patches from removing the open attribute showModal sets" do
      [mounted] = attr_of(render_dialog(), "dialog#delete-thing", "phx-mounted")
      assert mounted =~ "ignore_attrs"
      assert mounted =~ "open"
    end

    test "is labelled by its title" do
      doc = render_dialog()
      [labelledby] = attr_of(doc, "dialog", "aria-labelledby")

      assert doc |> LazyHTML.query("##{labelledby}") |> LazyHTML.text() == "Delete this thing?"
    end

    test "renders the body" do
      assert render_dialog() |> LazyHTML.query("dialog p") |> LazyHTML.text() =~
               "It goes away for good."
    end

    test "Cancel comes first and is marked for the hook to focus" do
      doc = render_dialog()
      buttons = LazyHTML.query(doc, ".modal-action button")

      assert LazyHTML.attribute(buttons, "phx-click") == ["cancel_delete", "confirm_delete"]
      assert LazyHTML.attribute(buttons, "type") == ["button", "button"]

      assert attr_of(doc, "button[data-confirm-dialog-cancel]", "phx-click") == ["cancel_delete"]
    end

    test "the confirm button uses the given label and style" do
      doc = render_dialog(confirm_label: "Publish", confirm_class: "btn-warning")
      [class] = attr_of(doc, "button[phx-click=confirm_delete]", "class")

      assert class =~ "btn-warning"

      assert doc |> LazyHTML.query("button[phx-click=confirm_delete]") |> LazyHTML.text() =~
               "Publish"
    end

    test "clicking the backdrop cancels" do
      assert attr_of(render_dialog(), ".modal-backdrop", "phx-click") == ["cancel_delete"]
    end

    test "no publish dialog claims publishing can't be undone" do
      # You can still edit or delete after publishing; only returning to draft is gone.
      offenders =
        for path <- Path.wildcard("lib/revix_web/live/*.heex"),
            File.read!(path) =~ "Once published, this cannot be undone.",
            do: path

      assert offenders == []
    end

    test "every dialog in the web layer uses this component" do
      offenders =
        for path <- Path.wildcard("lib/revix_web/**/*.{ex,heex}"),
            path != "lib/revix_web/components/core_components.ex",
            File.read!(path) =~ "<dialog",
            do: path

      assert offenders == []
    end
  end
end
