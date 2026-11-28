defmodule Revix.People.ScopeTest do
  use ExUnit.Case, async: true

  alias Revix.People.Person
  alias Revix.People.Scope

  defp scope(role), do: Scope.for_person(%Person{role: role})

  describe "owner?/1" do
    test "is true only for an owner" do
      assert Scope.owner?(scope(:owner))
      refute Scope.owner?(scope(:contributor))
      refute Scope.owner?(scope(:user))
    end

    test "is false for a signed-out visitor" do
      refute Scope.owner?(nil)
    end
  end

  describe "contributor?/1" do
    test "is true for owners and contributors" do
      assert Scope.contributor?(scope(:owner))
      assert Scope.contributor?(scope(:contributor))
    end

    test "is false for other people and signed-out visitors" do
      refute Scope.contributor?(scope(:user))
      refute Scope.contributor?(nil)
    end
  end
end
