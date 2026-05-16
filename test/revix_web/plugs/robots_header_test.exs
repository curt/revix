defmodule RevixWeb.Plugs.RobotsHeaderTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias RevixWeb.Plugs.RobotsHeader

  defp build_conn(format) do
    conn(:get, "/")
    |> put_private(:phoenix_format, format)
  end

  defp run(conn, opts \\ []) do
    opts = RobotsHeader.init(opts)
    conn = RobotsHeader.call(conn, opts)
    send_resp(conn, 200, "ok")
  end

  defp robots_tag(conn) do
    conn |> get_resp_header("x-robots-tag") |> List.first()
  end

  describe "HTML responses (default options)" do
    test "sets noindex, follow" do
      conn = "html" |> build_conn() |> run()
      assert robots_tag(conn) == "noindex, follow"
    end
  end

  describe "HTML responses (allow_index: true)" do
    test "sets index, follow" do
      conn = "html" |> build_conn() |> run(allow_index: true)
      assert robots_tag(conn) == "index, follow"
    end
  end

  describe "non-HTML responses" do
    test "json sets noindex, nofollow" do
      conn = "json" |> build_conn() |> run()
      assert robots_tag(conn) == "noindex, nofollow"
    end

    test "json ignores allow_index: true" do
      conn = "json" |> build_conn() |> run(allow_index: true)
      assert robots_tag(conn) == "noindex, nofollow"
    end

    test "activity sets noindex, nofollow" do
      conn = "activity" |> build_conn() |> run()
      assert robots_tag(conn) == "noindex, nofollow"
    end

    test "geo sets noindex, nofollow" do
      conn = "geo" |> build_conn() |> run()
      assert robots_tag(conn) == "noindex, nofollow"
    end
  end

  describe "no format set" do
    test "nil format sets noindex, nofollow" do
      conn = build_conn(nil) |> run()
      assert robots_tag(conn) == "noindex, nofollow"
    end
  end
end
