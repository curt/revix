defmodule Revix.Markdown.BackfillTest do
  use Revix.DataCase, async: true

  import Ecto.Query
  import Revix.EntriesFixtures
  import Revix.MediaFixtures
  import Revix.PlacesFixtures

  alias Revix.Entries.Entry
  alias Revix.Markdown.Backfill
  alias Revix.Media.Image
  alias Revix.Places.Place

  @unsafe "<p>hi</p><script>alert(1)</script>"
  @safe "<p>hi</p>alert(1)"

  defp put_html(schema, id, field, html) do
    Repo.update_all(from(r in schema, where: r.id == ^id), set: [{field, html}])
  end

  test "sanitizes stored entry, place, and image html and counts the rows it changed" do
    entry = checkin_fixture()
    place = place_fixture()
    image = image_fixture()
    put_html(Entry, entry.id, :content_html, @unsafe)
    put_html(Place, place.id, :content_html, @unsafe)
    put_html(Image, image.id, :caption_html, @unsafe)

    assert Backfill.run() == %{entries: 1, places: 1, images: 1}

    assert Repo.get!(Entry, entry.id).content_html == @safe
    assert Repo.get!(Place, place.id).content_html == @safe
    assert Repo.get!(Image, image.id).caption_html == @safe
  end

  test "leaves already-safe and nil html alone" do
    safe_entry = checkin_fixture()
    nil_entry = checkin_fixture()
    put_html(Entry, safe_entry.id, :content_html, "<p>fine</p>")
    put_html(Entry, nil_entry.id, :content_html, nil)

    assert Backfill.run() == %{entries: 0, places: 0, images: 0}

    assert Repo.get!(Entry, safe_entry.id).content_html == "<p>fine</p>"
    assert Repo.get!(Entry, nil_entry.id).content_html == nil
  end
end
