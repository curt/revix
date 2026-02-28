defmodule RevixWeb.IdenticonController do
  use RevixWeb, :controller

  @max_size 256
  @default_size 128
  @one_year 31_536_000

  def show(conn, %{"id" => id} = params) do
    size = parse_size(params["size"])
    etag = ~s("identicon-#{id}-#{size}")

    if get_req_header(conn, "if-none-match") == [etag] do
      send_resp(conn, 304, "")
    else
      conn
      |> put_resp_content_type("image/png")
      |> put_resp_header("cache-control", "public, max-age=#{@one_year}, immutable")
      |> put_resp_header("etag", etag)
      |> send_resp(200, Revix.Identicon.generate(id, size))
    end
  end

  defp parse_size(nil), do: @default_size

  defp parse_size(size_str) do
    case Integer.parse(size_str) do
      {size, _} when size > 0 -> min(size, @max_size)
      _ -> @default_size
    end
  end
end
