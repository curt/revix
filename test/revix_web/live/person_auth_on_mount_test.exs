defmodule RevixWeb.Live.PersonAuthOnMountTest do
  use ExUnit.Case, async: true

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
end
