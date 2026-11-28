defmodule RevixWeb.Live.PersonAuthOnMountTest do
  use Revix.DataCase, async: true

  alias Revix.People.Person
  alias Revix.People.Scope
  alias RevixWeb.Live.PersonAuth

  # The router's :require_owner plug turns non-owners away before a LiveView
  # mounts, so the live connection's own check is exercised directly here.
  defp socket(scope) do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, current_scope: scope, flash: %{}}
    }
  end

  describe "on_mount(:require_owner, ...)" do
    test "lets the owner through" do
      socket = socket(Scope.for_person(%Person{role: :owner}))
      assert {:cont, ^socket} = PersonAuth.on_mount(:require_owner, %{}, %{}, socket)
    end

    for role <- [:contributor, :user] do
      test "turns a #{role} away to the home page" do
        socket = socket(Scope.for_person(%Person{role: unquote(role)}))

        assert {:halt, halted} = PersonAuth.on_mount(:require_owner, %{}, %{}, socket)
        assert {:redirect, %{to: "/"}} = halted.redirected

        assert halted.assigns.flash["error"] ==
                 "You do not have permission to access this page."
      end
    end

    test "turns a signed-out visitor away" do
      assert {:halt, _} = PersonAuth.on_mount(:require_owner, %{}, %{}, socket(nil))
    end
  end

  describe "on_mount(:require_authenticated_person, ...)" do
    test "continues with the person's scope for a valid session" do
      person = Revix.PeopleFixtures.person_fixture()
      session = %{"person_token" => Revix.People.generate_person_session_token(person)}

      assert {:cont, socket} =
               PersonAuth.on_mount(:require_authenticated_person, %{}, session, socket(nil))

      assert socket.assigns.current_scope.person.id == person.id
    end

    test "sends a signed-out visitor to sign in" do
      assert {:halt, halted} =
               PersonAuth.on_mount(:require_authenticated_person, %{}, %{}, socket(nil))

      assert {:redirect, %{to: "/people/signin"}} = halted.redirected
      assert halted.assigns.flash["error"] == "You must sign in to access this page."
    end
  end

  describe "scope_from_session/1" do
    test "builds the scope for a valid session token" do
      person = Revix.PeopleFixtures.person_fixture()
      token = Revix.People.generate_person_session_token(person)

      assert %Scope{person: %Person{id: id}} =
               PersonAuth.scope_from_session(%{"person_token" => token})

      assert id == person.id
    end

    test "is nil without a token" do
      assert PersonAuth.scope_from_session(%{}) == nil
      assert PersonAuth.scope_from_session(%{"person_token" => nil}) == nil
    end

    test "is nil for a token that matches no session" do
      assert PersonAuth.scope_from_session(%{"person_token" => :crypto.strong_rand_bytes(32)}) ==
               nil
    end
  end
end
