defmodule Revix.OverpassTest do
  use ExUnit.Case, async: true

  alias Revix.Overpass

  describe "parse_elements/3" do
    test "parses node elements" do
      elements = %{
        "elements" => [
          %{
            "type" => "node",
            "id" => 123,
            "lat" => 40.001,
            "lon" => -105.001,
            "tags" => %{"name" => "Coffee Shop", "amenity" => "cafe"}
          }
        ]
      }

      assert [result] = Overpass.parse_elements(elements, 40.0, -105.0)
      assert result.name == "Coffee Shop"
      assert result.lat == 40.001
      assert result.lon == -105.001
      assert result.osm_type == :node
      assert result.osm_id == 123
      assert result.source == :osm
      assert result.id == nil
      assert is_float(result.distance)
      assert result.distance > 0
    end

    test "parses way elements using center coordinates" do
      elements = %{
        "elements" => [
          %{
            "type" => "way",
            "id" => 456,
            "center" => %{"lat" => 40.002, "lon" => -105.002},
            "tags" => %{"name" => "Big Building", "tourism" => "museum"}
          }
        ]
      }

      assert [result] = Overpass.parse_elements(elements, 40.0, -105.0)
      assert result.name == "Big Building"
      assert result.osm_type == :way
      assert result.osm_id == 456
      assert result.lat == 40.002
      assert result.lon == -105.002
    end

    test "parses relation elements using center coordinates" do
      elements = %{
        "elements" => [
          %{
            "type" => "relation",
            "id" => 789,
            "center" => %{"lat" => 40.003, "lon" => -105.003},
            "tags" => %{"name" => "Park Complex", "leisure" => "park"}
          }
        ]
      }

      assert [result] = Overpass.parse_elements(elements, 40.0, -105.0)
      assert result.osm_type == :relation
      assert result.osm_id == 789
    end

    test "skips elements without a name" do
      elements = %{
        "elements" => [
          %{
            "type" => "node",
            "id" => 111,
            "lat" => 40.001,
            "lon" => -105.001,
            "tags" => %{"amenity" => "bench"}
          }
        ]
      }

      assert [] = Overpass.parse_elements(elements, 40.0, -105.0)
    end

    test "sorts results by distance" do
      elements = %{
        "elements" => [
          %{
            "type" => "node",
            "id" => 1,
            "lat" => 40.01,
            "lon" => -105.01,
            "tags" => %{"name" => "Far"}
          },
          %{
            "type" => "node",
            "id" => 2,
            "lat" => 40.001,
            "lon" => -105.001,
            "tags" => %{"name" => "Near"}
          }
        ]
      }

      results = Overpass.parse_elements(elements, 40.0, -105.0)
      assert length(results) == 2
      assert Enum.at(results, 0).name == "Near"
      assert Enum.at(results, 1).name == "Far"
    end

    test "handles empty elements" do
      assert [] = Overpass.parse_elements(%{"elements" => []}, 40.0, -105.0)
    end

    test "handles missing elements key" do
      assert [] = Overpass.parse_elements(%{}, 40.0, -105.0)
    end

    test "uses the English name as the preferred name when it differs" do
      assert %{name: "Staroměstské náměstí", preferred_name: "Old Town Square"} =
               parse_one(%{"name" => "Staroměstské náměstí", "name:en" => "Old Town Square"})
    end

    test "falls back to int_name when there is no English name" do
      assert %{name: "東京駅", preferred_name: "Tokyo Station"} =
               parse_one(%{"name" => "東京駅", "int_name" => "Tokyo Station"})
    end

    test "prefers the English name over int_name" do
      assert %{preferred_name: "Old Town Square"} =
               parse_one(%{
                 "name" => "Staroměstské náměstí",
                 "name:en" => "Old Town Square",
                 "int_name" => "Staromestske namesti"
               })
    end

    test "has no preferred name when the English name equals the name, even if int_name differs" do
      assert %{preferred_name: nil} =
               parse_one(%{"name" => "Hostel", "name:en" => "Hostel", "int_name" => "Hostel Int"})
    end

    test "has no preferred name when int_name equals the name" do
      assert %{preferred_name: nil} = parse_one(%{"name" => "Cafe", "int_name" => "Cafe"})
    end

    test "has no preferred name when no alternate names exist" do
      assert %{preferred_name: nil} = parse_one(%{"name" => "Cafe"})
    end
  end

  defp parse_one(tags) do
    [result] =
      Overpass.parse_elements(
        %{
          "elements" => [
            %{"type" => "node", "id" => 1, "lat" => 40.0, "lon" => -105.0, "tags" => tags}
          ]
        },
        40.0,
        -105.0
      )

    result
  end
end

defmodule Revix.OverpassSearchTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Revix.Overpass

  @moduletag :capture_log

  describe "search_nearby/3" do
    test "includes admin_level relations enclosing the point" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "relation",
              "id" => 12345,
              "center" => %{"lat" => 40.0, "lon" => -105.0},
              "tags" => %{"name" => "Boulder County", "admin_level" => "6"}
            }
          ]
        })
      end)

      assert {:ok, [result]} = Overpass.search_nearby(40.0, -105.0, 500)
      assert result.name == "Boulder County"
      assert result.osm_type == :relation
      assert result.osm_id == 12345
    end

    test "defaults to English when no name language is configured" do
      original = Application.get_env(:revix, :overpass)
      Application.put_env(:revix, :overpass, Keyword.delete(original, :name_language))
      on_exit(fn -> Application.put_env(:revix, :overpass, original) end)

      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 1,
              "lat" => 40.0,
              "lon" => -105.0,
              "tags" => %{"name" => "Praha", "name:en" => "Prague", "name:de" => "Prag"}
            }
          ]
        })
      end)

      assert {:ok, [%{preferred_name: "Prague"}]} = Overpass.search_nearby(40.0, -105.0, 500)
    end

    test "uses the configured name language for the preferred name" do
      original = Application.get_env(:revix, :overpass)
      Application.put_env(:revix, :overpass, Keyword.put(original, :name_language, "de"))
      on_exit(fn -> Application.put_env(:revix, :overpass, original) end)

      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 1,
              "lat" => 40.0,
              "lon" => -105.0,
              "tags" => %{"name" => "Praha", "name:en" => "Prague", "name:de" => "Prag"}
            }
          ]
        })
      end)

      assert {:ok, [%{preferred_name: "Prag"}]} = Overpass.search_nearby(40.0, -105.0, 500)
    end

    test "logs failures with the search kind and duration" do
      Req.Test.stub(:overpass, fn conn -> Plug.Conn.send_resp(conn, 400, "parse error") end)

      log = capture_log(fn -> Overpass.search_nearby(40.0, -105.0, 500) end)

      assert log =~ ~r/\[overpass\] :search_nearby HTTP 400 \(\d+ms\): parse error/
    end

    test "logs a remark that accompanies partial results" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "remark" => "runtime error: out of memory",
          "elements" => [
            %{
              "type" => "node",
              "id" => 1,
              "lat" => 40.0,
              "lon" => -105.0,
              "tags" => %{"name" => "P"}
            }
          ]
        })
      end)

      log = capture_log(fn -> Overpass.search_nearby(40.0, -105.0, 500) end)

      assert log =~ "[overpass] :search_nearby remark"
      assert log =~ "runtime error: out of memory"
    end

    test "returns {:error, :unexpected_body} for a non-JSON 200 response" do
      Req.Test.stub(:overpass, fn conn -> Req.Test.html(conn, "<html>busy</html>") end)

      assert {:error, :unexpected_body} = Overpass.search_nearby(40.0, -105.0, 500)
    end

    test "returns a remark error when Overpass reports one with no elements" do
      remark = "runtime error: Query timed out in \"query\" at line 3 after 15 seconds."

      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{"remark" => remark, "elements" => []})
      end)

      assert {:error, {:overpass_remark, ^remark}} = Overpass.search_nearby(40.0, -105.0, 500)
    end

    test "keeps partial results when a remark accompanies elements" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "remark" => "runtime error: out of memory",
          "elements" => [
            %{
              "type" => "node",
              "id" => 1,
              "lat" => 40.001,
              "lon" => -105.001,
              "tags" => %{"name" => "Partial"}
            }
          ]
        })
      end)

      assert {:ok, [%{name: "Partial"}]} = Overpass.search_nearby(40.0, -105.0, 500)
    end

    test "requests only tags and center in the output" do
      stub_capturing_query()
      Overpass.search_nearby(40.0, -105.0, 500)

      assert_received {:query, query}
      assert query =~ "out tags center;"
      refute query =~ "out center;"
    end

    test "limits enclosing boundaries to local administrative levels" do
      stub_capturing_query()
      Overpass.search_nearby(40.0, -105.0, 500)

      assert_received {:query, query}

      assert query =~
               ~s|rel(pivot.containing)[name][boundary=administrative][admin_level~"^([6-9]\|10)$"];|
    end

    test "runs the spatial search once without a regex key filter" do
      stub_capturing_query()
      Overpass.search_nearby(40.0, -105.0, 500)

      assert_received {:query, query}
      assert length(String.split(query, "around:")) == 2
      assert query =~ "nwr(around:500,40.0,-105.0)[name]->.named;"
      refute query =~ ~s|[~"|

      for filter <- ~w(nwr.named[tourism] nwr.named[amenity] nwr.named[historic]
                       nwr.named[leisure] nwr.named[shop] nwr.named[aeroway=aerodrome]
                       nwr.named[railway=station] node.named[highway=bus_stop]
                       node.named[railway=tram_stop]) do
        assert query =~ filter <> ";"
      end
    end

    test "declares a 10 second timeout and 64 MiB maxsize" do
      stub_capturing_query()
      Overpass.search_nearby(40.0, -105.0, 500)

      assert_received {:query, query}
      assert String.starts_with?(query, "[out:json][timeout:10][maxsize:67108864];")
    end

    test "retries a failed search only once" do
      calls = :counters.new(1, [])

      Req.Test.stub(:overpass, fn conn ->
        :counters.add(calls, 1, 1)
        Plug.Conn.send_resp(conn, 504, "Gateway Timeout")
      end)

      assert {:error, {:http_error, 504}} = Overpass.search_nearby(40.0, -105.0, 500)
      assert :counters.get(calls, 1) == 2
    end

    test "resolves enclosing areas outside the output set" do
      stub_capturing_query()
      Overpass.search_nearby(40.0, -105.0, 500)

      assert_received {:query, query}
      [before_union, union] = String.split(query, "\n(\n", parts: 2)

      assert before_union =~ "is_in(40.0,-105.0)->.containing;"
      refute union =~ "is_in("
      assert union =~ "rel(pivot.containing)"
    end
  end

  defp stub_capturing_query(body \\ %{"elements" => []}) do
    test_pid = self()

    Req.Test.stub(:overpass, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:query, URI.decode_query(raw)["data"]})
      Req.Test.json(conn, body)
    end)
  end
end

defmodule Revix.OverpassFetchTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Revix.Overpass

  @moduletag :capture_log

  describe "fetch_element/2" do
    test "returns name and coordinates for a node" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 123,
              "lat" => 51.5,
              "lon" => -0.1,
              "tags" => %{"name" => "Some Cafe"}
            }
          ]
        })
      end)

      assert {:ok, %{name: "Some Cafe", lat: 51.5, lon: -0.1}} =
               Overpass.fetch_element(:node, 123)
    end

    test "returns center coordinates for a way" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "way",
              "id" => 456,
              "center" => %{"lat" => 48.8, "lon" => 2.3},
              "tags" => %{"name" => "Big Museum"}
            }
          ]
        })
      end)

      assert {:ok, %{name: "Big Museum", lat: 48.8, lon: 2.3}} =
               Overpass.fetch_element(:way, 456)
    end

    test "returns center coordinates for a relation" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "relation",
              "id" => 789,
              "center" => %{"lat" => 40.7, "lon" => -74.0},
              "tags" => %{"name" => "City Park"}
            }
          ]
        })
      end)

      assert {:ok, %{name: "City Park", lat: 40.7, lon: -74.0}} =
               Overpass.fetch_element(:relation, 789)
    end

    test "returns {:error, :not_found} on empty elements list" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{"elements" => []})
      end)

      assert {:error, :not_found} = Overpass.fetch_element(:node, 999)
    end

    test "returns {:error, :not_found} when element has no name" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 111,
              "lat" => 51.5,
              "lon" => -0.1,
              "tags" => %{"amenity" => "bench"}
            }
          ]
        })
      end)

      assert {:error, :not_found} = Overpass.fetch_element(:node, 111)
    end

    test "returns http error tuple on non-200 response after retrying" do
      calls = :counters.new(1, [])

      Req.Test.stub(:overpass, fn conn ->
        :counters.add(calls, 1, 1)

        conn
        |> Plug.Conn.put_status(429)
        |> Plug.Conn.send_resp(429, "Too Many Requests")
      end)

      assert {:error, {:http_error, 429}} = Overpass.fetch_element(:node, 123)
      assert :counters.get(calls, 1) == 3
    end

    test "succeeds when a transient failure is followed by a 200" do
      calls = :counters.new(1, [])

      Req.Test.stub(:overpass, fn conn ->
        :counters.add(calls, 1, 1)
        attempt = :counters.get(calls, 1)
        respond_after_transient(conn, attempt)
      end)

      assert {:ok, %{name: "Some Cafe"}} = Overpass.fetch_element(:node, 123)
      assert :counters.get(calls, 1) == 2
    end

    test "logs the status, retry-after, and body of a non-200 response" do
      Req.Test.stub(:overpass, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "0")
        |> Plug.Conn.send_resp(429, "Too Many Requests")
      end)

      log = capture_log(fn -> Overpass.fetch_element(:node, 123) end)

      assert log =~ "[overpass] {:fetch, :node, 123} HTTP 429"
      assert log =~ "retry-after=0"
      assert log =~ "Too Many Requests"
    end

    test "logs transport errors" do
      Req.Test.stub(:overpass, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      log = capture_log(fn -> Overpass.fetch_element(:node, 123) end)

      assert log =~ "[overpass] {:fetch, :node, 123} transport error"
      assert log =~ "reason: :timeout"
    end

    test "logs an Overpass remark" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{"remark" => "runtime error: out of memory", "elements" => []})
      end)

      log = capture_log(fn -> Overpass.fetch_element(:node, 123) end)

      assert log =~ "[overpass] {:fetch, :node, 123} remark"
      assert log =~ "runtime error: out of memory"
    end

    test "logs an unexpected body" do
      Req.Test.stub(:overpass, fn conn -> Req.Test.html(conn, "<html>\n  busy\n</html>") end)

      log = capture_log(fn -> Overpass.fetch_element(:node, 123) end)

      assert log =~ "[overpass] {:fetch, :node, 123} unexpected body"
      assert log =~ "<html> busy </html>"
    end

    test "truncates long bodies in the log" do
      Req.Test.stub(:overpass, fn conn ->
        Plug.Conn.send_resp(conn, 400, String.duplicate("x", 2_000))
      end)

      log = capture_log(fn -> Overpass.fetch_element(:node, 123) end)

      [line] = log |> String.split("\n") |> Enum.filter(&(&1 =~ "[overpass]"))
      assert line =~ "xxxx"
      assert String.length(line) < 600
    end

    test "logs nothing at warning level on success" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 1,
              "lat" => 51.5,
              "lon" => -0.1,
              "tags" => %{"name" => "Cafe"}
            }
          ]
        })
      end)

      log = capture_log([level: :warning], fn -> Overpass.fetch_element(:node, 1) end)

      refute log =~ "[overpass]"
    end

    test "logs a decoded JSON error body" do
      Req.Test.stub(:overpass, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "bad query"})
      end)

      log = capture_log(fn -> Overpass.fetch_element(:node, 123) end)

      assert log =~ "[overpass] {:fetch, :node, 123} HTTP 400"
      assert log =~ ~s(%{"error" => "bad query"})
    end

    test "uses Req's default retry delay when none is configured" do
      original = Application.get_env(:revix, :overpass)
      Application.put_env(:revix, :overpass, Keyword.delete(original, :retry_delay))
      on_exit(fn -> Application.put_env(:revix, :overpass, original) end)

      Req.Test.stub(:overpass, fn conn -> respond_after_transient(conn, 2) end)

      assert {:ok, %{name: "Some Cafe"}} = Overpass.fetch_element(:node, 123)
    end

    test "does not retry a 400 bad request" do
      calls = :counters.new(1, [])

      Req.Test.stub(:overpass, fn conn ->
        :counters.add(calls, 1, 1)
        Plug.Conn.send_resp(conn, 400, "parse error")
      end)

      assert {:error, {:http_error, 400}} = Overpass.fetch_element(:node, 123)
      assert :counters.get(calls, 1) == 1
    end

    test "returns error tuple on transport error" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, _} = Overpass.fetch_element(:node, 123)
    end

    test "returns {:error, :unexpected_body} for a non-JSON 200 response" do
      Req.Test.stub(:overpass, fn conn -> Req.Test.html(conn, "<html>busy</html>") end)

      assert {:error, :unexpected_body} = Overpass.fetch_element(:node, 123)
    end

    test "returns a remark error when Overpass reports one with no elements" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{"remark" => "runtime error: out of memory", "elements" => []})
      end)

      assert {:error, {:overpass_remark, "runtime error: out of memory"}} =
               Overpass.fetch_element(:node, 123)
    end

    test "requests only tags and center with tight limits" do
      stub_capturing_query()
      Overpass.fetch_element(:way, 456)

      assert_received {:query, query}
      assert String.starts_with?(query, "[out:json][timeout:15][maxsize:67108864];")
      assert query =~ "way(456);"
      assert query =~ "out tags center;"
      refute query =~ "out center;"
    end
  end

  defp stub_capturing_query(body \\ %{"elements" => []}) do
    test_pid = self()

    Req.Test.stub(:overpass, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:query, URI.decode_query(raw)["data"]})
      Req.Test.json(conn, body)
    end)
  end

  describe "API endpoint" do
    setup do
      original = Application.get_env(:revix, :overpass)
      on_exit(fn -> Application.put_env(:revix, :overpass, original) end)
      %{original: original}
    end

    test "defaults to the public overpass-api.de interpreter", %{original: original} do
      Application.put_env(:revix, :overpass, Keyword.delete(original, :api_url))

      assert request_target() == {:https, "overpass-api.de", "/api/interpreter"}
    end

    test "appends /interpreter to a configured base URL", %{original: original} do
      put_api_url(original, "https://api.overpass.ch/v1/KEY")

      assert request_target() == {:https, "api.overpass.ch", "/v1/KEY/interpreter"}
    end

    test "ignores trailing slashes on the base URL", %{original: original} do
      for url <- ["https://api.overpass.ch/v1/KEY/", "https://api.overpass.ch/v1/KEY//"] do
        put_api_url(original, url)

        assert request_target() == {:https, "api.overpass.ch", "/v1/KEY/interpreter"}
      end
    end

    test "falls back to the default for a blank base URL", %{original: original} do
      for url <- ["", "   "] do
        put_api_url(original, url)

        assert request_target() == {:https, "overpass-api.de", "/api/interpreter"}
      end
    end

    test "trims surrounding whitespace from the base URL", %{original: original} do
      put_api_url(original, "  https://api.overpass.ch/v1/KEY/  ")

      assert request_target() == {:https, "api.overpass.ch", "/v1/KEY/interpreter"}
    end

    test "does not double an /interpreter suffix", %{original: original} do
      for url <- [
            "https://api.overpass.ch/v1/KEY/interpreter",
            "https://api.overpass.ch/v1/KEY/interpreter/"
          ] do
        put_api_url(original, url)

        assert request_target() == {:https, "api.overpass.ch", "/v1/KEY/interpreter"}
      end
    end

    test "never logs the API key", %{original: original} do
      put_api_url(original, "https://api.overpass.ch/v1/SECRETKEY")

      Req.Test.stub(:overpass, fn conn -> Plug.Conn.send_resp(conn, 500, "Server Error") end)
      http_log = capture_log(fn -> Overpass.fetch_element(:node, 123) end)

      Req.Test.stub(:overpass, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
      transport_log = capture_log(fn -> Overpass.search_nearby(40.0, -105.0, 500) end)

      assert http_log =~ "[overpass]"
      assert transport_log =~ "[overpass]"
      refute http_log =~ "SECRETKEY"
      refute transport_log =~ "SECRETKEY"
    end
  end

  describe "bearer token" do
    setup do
      original = Application.get_env(:revix, :overpass)
      on_exit(fn -> Application.put_env(:revix, :overpass, original) end)
      %{original: original}
    end

    test "sends the configured token as an Authorization header", %{original: original} do
      put_bearer_token(original, "secret-token-123")

      test_pid = self()

      Req.Test.stub(:overpass, fn conn ->
        send(test_pid, {:headers, conn.req_headers})
        Req.Test.json(conn, %{"elements" => []})
      end)

      assert {:error, :not_found} = Overpass.fetch_element(:node, 1)
      assert_received {:headers, headers}
      assert {"authorization", "Bearer secret-token-123"} in headers
    end

    test "omits the Authorization header when no token is configured", %{original: original} do
      Application.put_env(:revix, :overpass, Keyword.delete(original, :bearer_token))

      test_pid = self()

      Req.Test.stub(:overpass, fn conn ->
        send(test_pid, {:headers, conn.req_headers})
        Req.Test.json(conn, %{"elements" => []})
      end)

      assert {:error, :not_found} = Overpass.fetch_element(:node, 1)
      assert_received {:headers, headers}
      refute Enum.any?(headers, &(elem(&1, 0) == "authorization"))
    end

    test "treats a blank token as unconfigured", %{original: original} do
      put_bearer_token(original, "")

      test_pid = self()

      Req.Test.stub(:overpass, fn conn ->
        send(test_pid, {:headers, conn.req_headers})
        Req.Test.json(conn, %{"elements" => []})
      end)

      assert {:error, :not_found} = Overpass.fetch_element(:node, 1)
      assert_received {:headers, headers}
      refute Enum.any?(headers, &(elem(&1, 0) == "authorization"))
    end

    test "never logs the bearer token", %{original: original} do
      put_bearer_token(original, "secret-token-123")

      Req.Test.stub(:overpass, fn conn -> Plug.Conn.send_resp(conn, 400, "parse error") end)
      log = capture_log(fn -> Overpass.fetch_element(:node, 123) end)

      assert log =~ "[overpass] {:fetch, :node, 123} HTTP 400"
      refute log =~ "secret-token-123"
    end
  end

  defp put_api_url(original, url) do
    Application.put_env(:revix, :overpass, Keyword.put(original, :api_url, url))
  end

  defp put_bearer_token(original, token) do
    Application.put_env(:revix, :overpass, Keyword.put(original, :bearer_token, token))
  end

  defp request_target do
    test_pid = self()

    Req.Test.stub(:overpass, fn conn ->
      send(test_pid, {:target, {conn.scheme, conn.host, conn.request_path}})
      Req.Test.json(conn, %{"elements" => []})
    end)

    Overpass.fetch_element(:node, 1)
    assert_received {:target, target}
    target
  end

  defp respond_after_transient(conn, 1), do: Plug.Conn.send_resp(conn, 504, "Gateway Timeout")

  defp respond_after_transient(conn, _attempt) do
    Req.Test.json(conn, %{
      "elements" => [
        %{
          "type" => "node",
          "id" => 123,
          "lat" => 51.5,
          "lon" => -0.1,
          "tags" => %{"name" => "Some Cafe"}
        }
      ]
    })
  end
end
