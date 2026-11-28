defmodule Revix.Federation.OriginTest do
  use ExUnit.Case, async: true

  alias Revix.Federation.Origin

  describe "same?/2" do
    test "is true for URIs on the same scheme, host, and port" do
      assert Origin.same?("https://a.example/users/1", "https://a.example/notes/2")
    end

    test "ignores the case of the host" do
      assert Origin.same?("https://A.Example/users/1", "https://a.example/notes/2")
    end

    test "is false for a different host" do
      refute Origin.same?("https://a.example/users/1", "https://b.example/notes/2")
    end

    test "is false for a subdomain of the same host" do
      refute Origin.same?("https://a.example/users/1", "https://evil.a.example/notes/2")
    end

    test "is false for a different scheme" do
      refute Origin.same?("https://a.example:8000/users/1", "http://a.example:8000/notes/2")
    end

    test "is false for a different port" do
      refute Origin.same?("https://a.example/users/1", "https://a.example:8443/notes/2")
    end

    test "is false when neither URI has a host" do
      refute Origin.same?("notes/1", "notes/2")
    end

    test "is false for non-strings" do
      refute Origin.same?(nil, "https://a.example/notes/2")
      refute Origin.same?("https://a.example/users/1", nil)
    end
  end
end
