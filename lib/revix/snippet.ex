defmodule Revix.Snippet do
  @moduledoc false

  @tags ~w(p em strong ol ul li)

  def snippify(markdown, max) when is_binary(markdown) and is_integer(max) and max > 0 do
    with {:ok, ast, _} <- Earmark.as_ast(preprocess(markdown)) do
      ast |> reduce() |> Enum.reverse() |> take(max) |> postprocess()
    end
  end

  def snippify(markdown, _max) when is_binary(markdown), do: ""

  def snippify(markdown, max) do
    snippify(to_string(markdown), max)
  end

  defp preprocess(markdown) do
    String.replace(markdown, ~r/\n{2,}/, " \n\n")
  end

  defp postprocess(markdown) do
    markdown
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\s+([,;:!?])/u, "\\1")
    |> String.replace(~r/\s+\.(?!\.)/u, ".")
  end

  defp take([], _max), do: ""

  defp take(list, max) when max > 0 do
    {acc, _used} =
      Enum.reduce_while(list, {[], 0}, fn word, state ->
        step_take(word, state, max)
      end)

    words = Enum.reverse(acc)
    truncated? = length(words) < length(list)

    # Maintainer note: we intentionally add an ellipsis only when at least one word
    # was omitted; full fits should round-trip without suffix.
    render_taken_words(words, truncated?)
  end

  defp step_take(word, {acc, used}, max) do
    next_size = used + separator_size(acc) + String.length(word)
    step_take_result(next_size <= max, word, acc, used, next_size)
  end

  defp step_take_result(true, word, acc, _used, next_size), do: {:cont, {[word | acc], next_size}}
  defp step_take_result(false, _word, acc, used, _next_size), do: {:halt, {acc, used}}

  defp separator_size([]), do: 0
  defp separator_size(_acc), do: 1

  defp render_taken_words(words, false), do: Enum.join(words, " ")
  defp render_taken_words([], true), do: ""
  defp render_taken_words(words, true), do: Enum.join(words ++ ["..."], " ")

  defp reduce(ast, start \\ [])

  defp reduce(ast, start) when is_list(ast) do
    Enum.reduce(ast, start, fn x, acc ->
      reduce(x, acc)
    end)
  end

  defp reduce(text, acc) when is_binary(text) do
    # Maintainer note: using `Enum.reverse/2` avoids quadratic growth from `acc ++ ...`.
    Enum.reverse(String.split(text), acc)
  end

  defp reduce({tag, _attrs, inner, _}, acc) when tag in @tags do
    # Maintainer note: we intentionally drop text from non-content tags
    # (e.g. code blocks, links, headings) to keep short snippets clean.
    reduce(inner, acc)
  end

  defp reduce({_tag, _attrs, _inner, _meta}, acc), do: acc
end
