defmodule Revix.Notifications.DigestNotifier do
  @moduledoc """
  Builds the subscriber digest email (plain text + HTML).

  The subject carries the run timestamp so each digest threads as a separate
  conversation in the recipient's mail client. An RFC 8058 `List-Unsubscribe`
  header points at the notification settings page.
  """

  import Swoosh.Email

  alias Revix.Mailer
  alias Revix.Notifications.Notification
  alias Revix.People.Person

  # Section order and headings for grouping notifications by type.
  @sections [
    owner_entry: "New posts",
    followed_entry: "From people you follow",
    companion_tag: "Tagged",
    reply: "Comments",
    like: "Likes",
    registration: "New members"
  ]

  @doc """
  Builds a `%Swoosh.Email{}` for `subscriber` covering `notifications`.

  `ctx` is a map with `:run_at` (DateTime), `:settings_url` (string or nil),
  and `:site_title` (string).
  """
  def build(%Person{} = subscriber, notifications, ctx) do
    new()
    |> to(subscriber.email)
    |> from(Mailer.sender(ctx[:site_title]))
    |> maybe_list_unsubscribe(ctx[:settings_url])
    |> subject(subject_line(ctx))
    |> text_body(render_text(notifications, ctx))
    |> html_body(render_html(notifications, ctx))
  end

  defp maybe_list_unsubscribe(email, nil), do: email

  defp maybe_list_unsubscribe(email, settings_url) do
    header(email, "List-Unsubscribe", "<#{settings_url}>")
  end

  defp subject_line(%{run_at: run_at} = ctx) do
    "#{site_title(ctx)} activity — #{Calendar.strftime(run_at, "%b %-d, %Y %H:%M UTC")}"
  end

  defp site_title(ctx), do: ctx[:site_title] || "Revix"

  ## Plain text

  defp render_text(notifications, ctx) do
    sections =
      notifications
      |> group()
      |> Enum.map_join("\n\n", &text_section/1)

    """

    ==============================

    #{site_title(ctx)} activity digest

    ==============================

    #{sections}

    ==============================

    #{text_footer(ctx)}
    """
  end

  defp text_section({heading, entries}) do
    lines = Enum.map_join(entries, "\n", &text_line/1)
    "#{heading}\n#{String.duplicate("-", String.length(heading))}\n#{lines}"
  end

  defp text_line(%Notification{summary: summary, url: nil}), do: "* #{summary}"
  defp text_line(%Notification{summary: summary, url: url}), do: "* #{summary}\n  #{url}"

  defp text_footer(ctx),
    do: text_settings_line(ctx[:settings_url]) <> "\nPlease do not reply to this message."

  defp text_settings_line(nil), do: "Change your notification frequency in your account settings."

  defp text_settings_line(url), do: "Change your notification frequency: #{url}"

  ## HTML

  defp render_html(notifications, ctx) do
    sections =
      notifications
      |> group()
      |> Enum.map_join("\n", &html_section/1)

    """
    <h2>#{site_title(ctx)} activity digest</h2>
    #{sections}
    <hr>
    <p>#{html_footer(ctx)}</p>
    """
  end

  defp html_section({heading, entries}) do
    items = Enum.map_join(entries, "\n", &html_line/1)
    "<h3>#{heading}</h3>\n<ul>\n#{items}\n</ul>"
  end

  defp html_line(%Notification{summary: summary, url: nil}),
    do: "<li>#{html_escape(summary)}</li>"

  defp html_line(%Notification{summary: summary, url: url}) do
    "<li>#{html_escape(summary)} &mdash; <a href=\"#{html_escape(url)}\">#{html_escape(url)}</a></li>"
  end

  defp html_footer(ctx) do
    html_settings_line(ctx[:settings_url]) <> " Please do not reply to this message."
  end

  defp html_settings_line(nil), do: "Change your notification frequency in your account settings."

  defp html_settings_line(url),
    do: "<a href=\"#{html_escape(url)}\">Change your notification frequency</a>."

  defp html_escape(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  ## Grouping

  defp group(notifications) do
    by_type = Enum.group_by(notifications, & &1.type)

    for {type, heading} <- @sections,
        entries = Map.get(by_type, type, []),
        entries != [] do
      {heading, entries}
    end
  end
end
