defmodule Revix.MarkdownTest do
  use ExUnit.Case, async: true

  alias Revix.Markdown

  describe "to_safe_html/1" do
    test "renders markdown formatting" do
      assert Markdown.to_safe_html("**bold** and *em* and [link](https://example.com)") ==
               {:ok,
                ~s(<p><strong>bold</strong> and <em>em</em> and <a href="https://example.com">link</a></p>)}
    end

    test "removes script blocks" do
      assert {:ok, html} = Markdown.to_safe_html("hi\n\n<script>alert(1)</script>")
      refute html =~ "<script"
      assert html =~ "<p>hi</p>"
    end

    test "removes javascript: link targets" do
      assert {:ok, html} = Markdown.to_safe_html("[x](javascript:alert(1))")
      refute html =~ "javascript:"
    end

    test "removes event handler attributes from raw html" do
      assert {:ok, html} = Markdown.to_safe_html(~s{<div><img src="x" onerror="alert(1)"></div>})
      refute html =~ "onerror"
    end

    test "keeps the basic tags remote servers send" do
      remote = ~s(<p>Hello <a href="https://remote.example/@a" class="mention">@a</a><br>bye</p>)
      assert {:ok, html} = Markdown.to_safe_html(remote)
      assert html =~ ~s(<a href="https://remote.example/@a">@a</a>)
      assert html =~ "<br"
    end

    test "returns an error when markdown cannot be rendered" do
      assert {:error, [_ | _]} = Markdown.to_safe_html("<div>\nunclosed")
    end
  end

  describe "sanitize/1" do
    test "returns nil for nil" do
      assert Markdown.sanitize(nil) == nil
    end

    test "strips scripts from stored html" do
      assert Markdown.sanitize("<p>ok</p><script>alert(1)</script>") == "<p>ok</p>alert(1)"
    end
  end
end
