defmodule Revix.SitesTest do
  use Revix.DataCase, async: true

  alias Revix.Sites
  alias Revix.Sites.Site

  @endpoint "https://example.test/"

  describe "get_site/1" do
    test "returns nil when no row exists" do
      assert Sites.get_site(@endpoint) == nil
    end

    test "returns the site row when one exists" do
      {:ok, site} = Sites.update_site(@endpoint, %{title: "My Site"})
      assert Sites.get_site(@endpoint) == site
    end
  end

  describe "get_site_or_default/1" do
    test "returns default title and description when no row exists" do
      site = Sites.get_site_or_default(@endpoint)
      assert site.title == "Revix"
      assert site.description =~ "federated"
      assert site.endpoint == @endpoint
    end

    test "returns the persisted row when one exists" do
      {:ok, _site} = Sites.update_site(@endpoint, %{title: "My Site", description: "Custom"})
      site = Sites.get_site_or_default(@endpoint)
      assert site.title == "My Site"
      assert site.description == "Custom"
    end

    test "falls back to the default when the persisted title is blank" do
      {:ok, _site} = Sites.update_site(@endpoint, %{title: ""})
      site = Sites.get_site_or_default(@endpoint)
      assert site.title == "Revix"
    end
  end

  describe "update_site/2" do
    test "creates a new row when none exists" do
      assert {:ok, %Site{title: "New Title"}} =
               Sites.update_site(@endpoint, %{title: "New Title"})
    end

    test "updates the existing row (upsert) rather than duplicating it" do
      {:ok, _} = Sites.update_site(@endpoint, %{title: "First"})
      {:ok, updated} = Sites.update_site(@endpoint, %{title: "Second"})

      assert updated.title == "Second"
      assert Sites.get_site(@endpoint).title == "Second"
    end

    test "returns {:error, changeset} when title exceeds the max length" do
      assert {:error, %Ecto.Changeset{}} =
               Sites.update_site(@endpoint, %{title: String.duplicate("a", 256)})
    end
  end

  describe "description_html/1" do
    test "returns nil when description is nil" do
      assert Sites.description_html(%Site{endpoint: @endpoint, description: nil}) == nil
    end

    test "renders markdown description to html" do
      site = %Site{endpoint: @endpoint, description: "**bold**"}
      assert Sites.description_html(site) =~ "<strong>bold</strong>"
    end
  end

  describe "page_title/1" do
    test "returns just the title when description is nil" do
      site = %Site{endpoint: @endpoint, title: "My Site", description: nil}
      assert Sites.page_title(site) == "My Site"
    end

    test "appends the full description when it fits" do
      site = %Site{endpoint: @endpoint, title: "My Site", description: "Short description"}
      assert Sites.page_title(site) == "My Site · Short description"
    end

    test "truncates a long description with an ellipsis" do
      site = %Site{
        endpoint: @endpoint,
        title: "My Site",
        description: String.duplicate("word ", 30)
      }

      page_title = Sites.page_title(site)
      assert page_title =~ "My Site · "
      assert page_title =~ "..."
    end
  end
end
