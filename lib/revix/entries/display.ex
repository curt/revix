defmodule Revix.Entries.Display do
  @moduledoc """
  Human-readable text for showing an entry, such as a checkin's place and time.
  """

  def checkin_display_content(%{content: content, content_html: html} = checkin)
      when is_binary(content) and content != "" do
    if String.trim(content) != "",
      do: html || content,
      else: checkin_display_content(%{checkin | content: nil})
  end

  def checkin_display_content(checkin) do
    place =
      get_in(checkin, [Access.key(:place), Access.key(:name)]) ||
        Map.get(checkin, :name) ||
        "somewhere"

    checkin_place_time_string(place, checkin_time_string(checkin))
  end

  defp checkin_time_string(%{starts_at_local: local, starts_tz: tz})
       when not is_nil(local) and not is_nil(tz) do
    formatted_time = local |> DateTime.from_naive!(tz) |> Calendar.strftime("%H:%M %Z")
    "#{Calendar.strftime(local, "%Y-%m-%d")} #{formatted_time}"
  end

  defp checkin_time_string(%{starts_at_utc: utc}) when not is_nil(utc) do
    Calendar.strftime(utc, "%Y-%m-%d %H:%M UTC")
  end

  defp checkin_time_string(_), do: nil

  defp checkin_place_time_string(place, nil), do: "Checked into #{place}."
  defp checkin_place_time_string(place, time), do: "Checked into #{place} #{time}."
end
