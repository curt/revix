defmodule Revix.Federation.SignedRequestTest do
  use ExUnit.Case, async: true

  alias Revix.Federation.SignedRequest

  @now ~U[2026-11-27 20:00:00Z]
  @body ~s({"type":"Like"})
  @sha256 "SHA-256=" <> Base.encode64(:crypto.hash(:sha256, @body))
  @sha512 "SHA-512=" <> Base.encode64(:crypto.hash(:sha512, @body))
  @signed ~S|keyId="https://remote.example/u#key",algorithm="rsa-sha256",headers="(request-target) host date digest",signature="abc"|

  defp headers(overrides \\ %{}) do
    Map.merge(
      %{
        "signature" => @signed,
        "date" => "Fri, 27 Nov 2026 20:00:00 GMT",
        "digest" => @sha256
      },
      overrides
    )
  end

  defp validate(overrides, body \\ @body),
    do: SignedRequest.validate(headers(overrides), body, @now)

  test "accepts a fresh request whose signature covers the required headers and body" do
    assert validate(%{}) == :ok
  end

  describe "signed headers" do
    test "rejects a signature that covers only the date (the library default)" do
      sig = ~S|keyId="https://remote.example/u#key",signature="abc"|
      assert validate(%{"signature" => sig}) == {:error, :unsigned_headers}
    end

    test "rejects a signature that leaves out the digest" do
      sig = ~S|keyId="k",headers="(request-target) host date",signature="abc"|
      assert validate(%{"signature" => sig}) == {:error, :unsigned_headers}
    end

    test "matches header names case-insensitively" do
      sig = ~S|keyId="k",headers="(request-target) Host Date Digest",signature="abc"|
      assert validate(%{"signature" => sig}) == :ok
    end

    test "rejects a missing signature header" do
      assert SignedRequest.validate(Map.delete(headers(), "signature"), @body, @now) ==
               {:error, :unsigned_headers}
    end
  end

  describe "date" do
    test "accepts a date just inside the window on either side" do
      assert validate(%{"date" => "Fri, 27 Nov 2026 19:00:00 GMT"}) == :ok
      assert validate(%{"date" => "Fri, 27 Nov 2026 21:00:00 GMT"}) == :ok
    end

    test "rejects a date outside the window on either side" do
      assert validate(%{"date" => "Fri, 27 Nov 2026 18:59:59 GMT"}) == {:error, :stale_date}
      assert validate(%{"date" => "Fri, 27 Nov 2026 21:00:01 GMT"}) == {:error, :stale_date}
    end

    test "rejects a missing or unparseable date" do
      assert SignedRequest.validate(Map.delete(headers(), "date"), @body, @now) ==
               {:error, :stale_date}

      assert validate(%{"date" => "yesterday"}) == {:error, :stale_date}
    end
  end

  describe "digest" do
    test "rejects a body that doesn't match the digest" do
      assert validate(%{}, ~s({"type":"Delete"})) == {:error, :invalid_digest}
    end

    test "accepts SHA-512 and lowercase algorithm names" do
      assert validate(%{"digest" => @sha512}) == :ok
      assert validate(%{"digest" => String.replace(@sha256, "SHA-256", "sha-256")}) == :ok
    end

    test "requires every listed digest to match" do
      assert validate(%{"digest" => @sha256 <> "," <> @sha512}) == :ok
      bad = "SHA-512=" <> Base.encode64(:crypto.hash(:sha512, "other"))
      assert validate(%{"digest" => @sha256 <> ", " <> bad}) == {:error, :invalid_digest}
    end

    test "rejects a missing digest or one with no supported algorithm" do
      assert SignedRequest.validate(Map.delete(headers(), "digest"), @body, @now) ==
               {:error, :invalid_digest}

      assert validate(%{"digest" => "MD5=abc"}) == {:error, :invalid_digest}
    end
  end
end
