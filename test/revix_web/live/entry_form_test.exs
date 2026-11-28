defmodule RevixWeb.Live.EntryFormTest do
  use ExUnit.Case, async: true

  alias RevixWeb.Live.EntryForm

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, image_captions: %{}, upload_captions: %{}}, assigns)
    }
  end

  describe "update_photo_field/4" do
    test "keeps the first value typed for a new upload" do
      socket = EntryForm.update_photo_field(socket(%{}), "phx-ref-1", :alt, "A cat")
      assert socket.assigns.upload_captions["phx-ref-1"] == %{caption: "", alt: "A cat"}
    end

    test "keeps the first caption typed for an existing image without one yet" do
      socket =
        %{image_captions: %{"img-1" => %{caption: "Old", alt: ""}}}
        |> socket()
        |> EntryForm.update_photo_field("img-1", :caption, "New")

      assert socket.assigns.image_captions["img-1"] == %{caption: "New", alt: ""}
    end
  end
end
