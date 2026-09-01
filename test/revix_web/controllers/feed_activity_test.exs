defmodule RevixWeb.FeedActivityTest do
  use ExUnit.Case, async: true

  alias RevixWeb.FeedActivity
  alias RevixWeb.FeedATOM
  alias RevixWeb.FeedRSS

  describe "effective_updated/1" do
    test "returns published_at_utc when there is no modification" do
      dt = ~U[2026-01-01 10:00:00Z]
      assert FeedActivity.effective_updated(%{modified_at_utc: nil, published_at_utc: dt}) == dt
    end

    test "returns modified_at_utc when it is later than published_at_utc" do
      published = ~U[2026-01-01 10:00:00Z]
      modified = ~U[2026-01-05 10:00:00Z]

      assert FeedActivity.effective_updated(%{
               modified_at_utc: modified,
               published_at_utc: published
             }) == modified
    end

    test "returns published_at_utc when the modification is not newer" do
      published = ~U[2026-01-10 10:00:00Z]
      modified = ~U[2026-01-05 10:00:00Z]

      assert FeedActivity.effective_updated(%{
               modified_at_utc: modified,
               published_at_utc: published
             }) == published
    end

    test "falls back to published_at_utc for maps without a modified_at_utc key" do
      dt = ~U[2026-01-01 10:00:00Z]
      assert FeedActivity.effective_updated(%{published_at_utc: dt}) == dt
    end
  end

  describe "datetime formatters handle nil" do
    test "Atom returns an empty string for a nil datetime" do
      assert FeedATOM.format_atom_datetime(nil) == ""
    end

    test "RSS returns an empty string for a nil datetime" do
      assert FeedRSS.format_rss_datetime(nil) == ""
    end
  end

  describe "FeedRSS.format_rss_datetime/1" do
    test "renders an RFC 822 date in GMT" do
      assert FeedRSS.format_rss_datetime(~U[2026-01-01 10:00:00Z]) ==
               "Thu, 01 Jan 2026 10:00:00 GMT"
    end
  end
end
