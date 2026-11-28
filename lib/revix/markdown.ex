defmodule Revix.Markdown do
  @moduledoc """
  The one place user-supplied or federated text becomes HTML.

  Earmark passes raw HTML blocks and `javascript:` link targets through
  untouched, and every `*_html` field is rendered with `raw/1`, so the output
  is always run through an allowlist sanitizer before it is stored or shown.
  """

  def to_safe_html(markdown) when is_binary(markdown) do
    markdown
    |> Earmark.as_html(compact_output: true)
    |> sanitize_result()
  end

  def sanitize(nil), do: nil
  def sanitize(html) when is_binary(html), do: HtmlSanitizeEx.basic_html(html)

  defp sanitize_result({:ok, html, _messages}), do: {:ok, sanitize(html)}
  defp sanitize_result({:error, _html, messages}), do: {:error, messages}
end
