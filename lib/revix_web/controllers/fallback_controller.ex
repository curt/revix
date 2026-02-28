defmodule RevixWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use RevixWeb, :controller

  # Handles a not found request.
  def call(_, {:error, :not_found}) do
    raise Plug.BadRequestError, plug_status: 404
  end

  # Handles an unauthorized request.
  def call(_, {:error, :unauthorized}) do
    raise Plug.BadRequestError, plug_status: 403
  end

  # Handles a bad request.
  def call(_, {:error, :bad_request}) do
    raise Plug.BadRequestError, plug_status: 400
  end
end
