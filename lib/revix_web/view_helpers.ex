defmodule RevixWeb.View.Helpers do
  @doc """
  Formats a NaiveDateTime with its IANA timezone into a string with the
  timezone abbreviation. The abbreviation reflects DST when applicable
  (e.g. "EST" vs "EDT" for America/New_York).

  When a UTC datetime is provided, it is used to unambiguously resolve
  the timezone offset during DST fall-back transitions (when the same
  wall clock time occurs twice).

  ## Examples

      iex> format_local_datetime(~N[2026-01-15 10:30:00], "America/New_York")
      "10:30 EST"

      iex> format_local_datetime(~N[2026-07-15 10:30:00], "America/New_York")
      "10:30 EDT"

      iex> format_local_datetime(~N[2026-10-25 02:30:00], "Europe/Paris", ~U[2026-10-25 00:30:00Z])
      "02:30 CEST"

      iex> format_local_datetime(~N[2026-10-25 02:30:00], "Europe/Paris", ~U[2026-10-25 01:30:00Z])
      "02:30 CET"
  """
  def format_local_datetime(%NaiveDateTime{} = local, tz) when is_binary(tz) do
    local
    |> DateTime.from_naive!(tz)
    |> Calendar.strftime("%H:%M %Z")
  end

  def format_local_datetime(%NaiveDateTime{} = _local, tz, %DateTime{} = utc)
      when is_binary(tz) do
    utc
    |> DateTime.shift_zone!(tz)
    |> Calendar.strftime("%H:%M %Z")
  end
end
