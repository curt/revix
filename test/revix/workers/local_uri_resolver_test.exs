defmodule Revix.Workers.LocalUriResolverTest do
  use Revix.DataCase, async: true

  alias Revix.Workers.LocalUriResolver

  import Revix.EntriesFixtures

  # The test endpoint is configured with url: [host: "localhost"] (from config.exs).
  # Fixtures that exercise the URL-fallback path use that host so extract_local_entry_id
  # matches and resolves to the canonical entry URI.
  @local_host "localhost"

  defp local_checkin do
    id = Revix.Ecto.Base58Id.autogenerate()
    uri = "http://#{@local_host}/checkins/#{id}"
    checkin_fixture(%{id: id, uri: uri, url: uri})
  end

  describe "resolve/1" do
    test "returns nil unchanged" do
      assert is_nil(LocalUriResolver.resolve(nil))
    end

    test "returns a remote URL unchanged" do
      assert LocalUriResolver.resolve("https://remote.example.com/posts/abc") ==
               "https://remote.example.com/posts/abc"
    end

    test "fast path: returns the canonical URI when given the URI directly" do
      checkin = local_checkin()
      assert LocalUriResolver.resolve(checkin.uri) == checkin.uri
    end

    test "URL fallback: resolves a local checkin display URL (with slug) to the canonical URI" do
      checkin = local_checkin()
      url_with_slug = checkin.uri <> "/some-place-slug"
      assert LocalUriResolver.resolve(url_with_slug) == checkin.uri
    end

    test "URL fallback: resolves a local checkin URL with multiple slug segments" do
      checkin = local_checkin()
      url_with_slugs = checkin.uri <> "/mexico/some-city/some-place"
      assert LocalUriResolver.resolve(url_with_slugs) == checkin.uri
    end

    test "URL fallback: returns the original value for a local-host URL with an unknown ID" do
      unknown_url = "http://#{@local_host}/checkins/unknownBadId/slug"
      assert LocalUriResolver.resolve(unknown_url) == unknown_url
    end

    test "URL fallback: returns the original value for a local-host URL with an unrecognized route prefix" do
      unknown_url = "http://#{@local_host}/people/someId/slug"
      assert LocalUriResolver.resolve(unknown_url) == unknown_url
    end
  end
end
