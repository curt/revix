defmodule RevixWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use RevixWeb, :controller

  def call(conn, {:error, :not_found}), do: respond(conn, 404, "Not Found")
  def call(conn, {:error, :tombstoned}), do: respond(conn, 410, "Gone")
  def call(conn, {:error, :unauthorized}), do: respond(conn, 403, "Forbidden")
  def call(conn, {:error, :invalid_signature}), do: respond(conn, 401, "Unauthorized")
  def call(conn, {:error, :bad_request}), do: respond(conn, 400, "Bad Request")
  def call(conn, {:error, :invalid_activity}), do: respond(conn, 400, "Bad Request")

  defp respond(conn, status, message) do
    respond_by_format(conn, get_format(conn), status, message)
  end

  defp respond_by_format(conn, "html", status, message) do
    conn |> put_status(status) |> text(message)
  end

  defp respond_by_format(conn, "activity", status, message) do
    activity(conn, %{"error" => message}, status: status)
  end

  defp respond_by_format(conn, _format, status, message) do
    conn |> put_status(status) |> json(%{errors: %{detail: message}})
  end
end
