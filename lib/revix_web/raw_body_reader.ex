defmodule RevixWeb.RawBodyReader do
  # Caches the raw request body in conn.assigns[:raw_body] so that
  # HTTP signature verification can access it after Plug.Parsers has consumed the body.

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = update_in(conn.assigns[:raw_body], &((&1 || "") <> body))
    {:ok, body, conn}
  end
end
