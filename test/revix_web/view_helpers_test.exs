defmodule RevixWeb.View.HelpersTest do
  use ExUnit.Case, async: true

  import RevixWeb.View.Helpers

  describe "format_local_datetime/2" do
    test "formats time with standard time abbreviation" do
      assert format_local_datetime(~N[2026-01-15 10:30:00], "America/New_York") == "10:30 EST"
    end

    test "formats time with daylight saving time abbreviation" do
      assert format_local_datetime(~N[2026-07-15 10:30:00], "America/New_York") == "10:30 EDT"
    end

    test "formats time for UTC timezone" do
      assert format_local_datetime(~N[2026-03-10 14:00:00], "Etc/UTC") == "14:00 UTC"
    end

    test "formats time for non-US timezone" do
      assert format_local_datetime(~N[2026-01-15 09:00:00], "Europe/London") == "09:00 GMT"
    end

    test "formats time for non-US daylight saving timezone" do
      assert format_local_datetime(~N[2026-07-15 09:00:00], "Europe/London") == "09:00 BST"
    end

    test "formats midnight correctly" do
      assert format_local_datetime(~N[2026-01-15 00:00:00], "America/Denver") == "00:00 MST"
    end

    test "raises on ambiguous wall clock time without UTC hint" do
      # Europe/Paris falls back on 2026-10-25: 3:00 CEST -> 2:00 CET
      # 2:30 AM local occurs twice, so from_naive! raises
      assert_raise ArgumentError, fn ->
        format_local_datetime(~N[2026-10-25 02:30:00], "Europe/Paris")
      end
    end
  end

  describe "format_local_datetime/3" do
    test "resolves ambiguous time to CEST with earlier UTC hint" do
      # UTC 00:30 corresponds to 02:30 CEST (before fall-back)
      assert format_local_datetime(
               ~N[2026-10-25 02:30:00],
               "Europe/Paris",
               ~U[2026-10-25 00:30:00Z]
             ) == "02:30 CEST"
    end

    test "resolves ambiguous time to CET with later UTC hint" do
      # UTC 01:30 corresponds to 02:30 CET (after fall-back)
      assert format_local_datetime(
               ~N[2026-10-25 02:30:00],
               "Europe/Paris",
               ~U[2026-10-25 01:30:00Z]
             ) == "02:30 CET"
    end

    test "works for unambiguous times with UTC hint" do
      assert format_local_datetime(
               ~N[2026-01-15 10:30:00],
               "America/New_York",
               ~U[2026-01-15 15:30:00Z]
             ) == "10:30 EST"
    end

    test "works for unambiguous DST times with UTC hint" do
      assert format_local_datetime(
               ~N[2026-07-15 10:30:00],
               "America/New_York",
               ~U[2026-07-15 14:30:00Z]
             ) == "10:30 EDT"
    end
  end
end
