defmodule RevixWeb.OwnerVisibilityTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Revix.People.Person
  alias Revix.People.Scope

  defp scope(role, uri \\ "https://example.com/people/me"),
    do: Scope.for_person(%Person{role: role, uri: uri, email: "me@example.com"})

  describe "navigation" do
    defp nav_hrefs(scope) do
      assigns = %{scope: scope, site: %Revix.Sites.Site{title: "Revix"}}

      ~H"""
      <RevixWeb.Layouts.app flash={%{}} current_scope={@scope} site={@site}>
        page
      </RevixWeb.Layouts.app>
      """
      |> rendered_to_string()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("a")
      |> LazyHTML.attribute("href")
    end

    @owner_links ~w(/posts/new /places/new /pings /settings/site)

    test "shows the owner-only links to the owner" do
      hrefs = nav_hrefs(scope(:owner))
      for link <- @owner_links, do: assert(link in hrefs, link)
    end

    test "hides the owner-only links from everyone else" do
      for role <- [:contributor, :user] do
        hrefs = nav_hrefs(scope(role))
        for link <- @owner_links, do: refute(link in hrefs, "#{role} sees #{link}")
      end
    end
  end

  describe "entry_owner_actions/1" do
    defp actions(scope, author_uri) do
      assigns = %{scope: scope, author: author_uri}

      ~H"""
      <RevixWeb.ActivityComponents.entry_owner_actions
        current_scope={@scope}
        entry_author_uri={@author}
        has_images={true}
        edit_href="/edit"
        retransform_href="/retransform"
        entry_label="checkin"
      />
      """
      |> rendered_to_string()
    end

    test "offers Re-transform photos to the owner on someone else's entry" do
      html = actions(scope(:owner), "https://example.com/people/someone-else")
      assert html =~ ~s(href="/retransform")
      refute html =~ ~s(href="/edit")
    end

    test "offers only Edit to an author who isn't the owner" do
      html = actions(scope(:contributor), "https://example.com/people/me")
      assert html =~ ~s(href="/edit")
      refute html =~ ~s(href="/retransform")
    end

    test "offers nothing to anyone else" do
      assert actions(scope(:user), "https://example.com/people/someone-else") =~ ~r/\A\s*\z/
    end
  end
end
