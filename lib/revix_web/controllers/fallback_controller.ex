defmodule RevixWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use RevixWeb, :controller

  def call(conn, {:error, :not_found}) do
    send_resp(conn, 404, "Not Found")
  end

  def call(conn, {:error, :unauthorized}) do
    send_resp(conn, 403, "Forbidden")
  end

  def call(conn, {:error, :bad_request}) do
    send_resp(conn, 400, "Bad Request")
  end
end
