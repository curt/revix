defmodule Revix.SnippetTest do
  use ExUnit.Case, async: true

  alias Revix.Snippet

  describe "snippify/2" do
    test "returns empty string for empty markdown" do
      assert Snippet.snippify("", 100) == ""
    end

    test "extracts text from allowed content tags" do
      markdown = """
      Paragraph with *emphasis* and **strong**.

      - item one
      - item two
      """

      assert Snippet.snippify(markdown, 300) ==
               "Paragraph with emphasis and strong. item one item two"
    end

    test "drops text from non-allowed tags like headings and links" do
      markdown = """
      # Hidden heading

      [Hidden link text](https://example.com)

      Visible paragraph
      """

      assert Snippet.snippify(markdown, 300) == "Visible paragraph"
    end

    test "normalizes excessive whitespace in output" do
      markdown = "first\n\n\nsecond"
      assert Snippet.snippify(markdown, 300) == "first second"
    end

    test "truncates and appends ellipsis when content exceeds max" do
      assert Snippet.snippify("one two three four", 10) == "one two ..."
    end

    test "does not append ellipsis when content fits max exactly" do
      assert Snippet.snippify("one two", 7) == "one two"
    end

    test "returns empty string when max is zero or negative" do
      assert Snippet.snippify("one two", 0) == ""
      assert Snippet.snippify("one two", -10) == ""
    end

    test "returns empty string when max is non-integer for binary markdown" do
      assert Snippet.snippify("one two", :infinity) == ""
    end

    test "coerces non-binary markdown to string before processing" do
      assert Snippet.snippify(12345, 10) == "12345"
    end

    test "coerces non-binary markdown then still applies max guards" do
      assert Snippet.snippify(12345, 0) == ""
    end

    test "returns empty string when first word cannot fit within max" do
      assert Snippet.snippify("encyclopedia tiny", 3) == ""
    end
  end
end
