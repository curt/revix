defmodule RevixWeb.InboxController do
  use RevixWeb, :controller

  alias Revix.People

  action_fallback RevixWeb.FallbackController

  def create(conn, %{"id" => person_id} = _params) do
    with {:ok, person} <- safe_get_local_person(person_id),
         :ok <- verify_signature(conn),
         :ok <- validate_activity(conn.body_params) do
      enqueue_activity(conn.body_params, person)
      send_resp(conn, 202, "")
    else
      {:error, :not_found} ->
        send_resp(conn, 404, "")

      {:error, :invalid_signature} ->
        send_resp(conn, 401, "")

      {:error, :invalid_activity} ->
        send_resp(conn, 400, "")
    end
  end

  defp safe_get_local_person(id) do
    People.get_local_person(id)
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp verify_signature(conn) do
    # Inject the (request-target) pseudo-header so HTTPSignatures can verify it.
    # The library builds the signing string from conn.req_headers, which doesn't
    # include this pseudo-header — we must add it manually.
    target = "post #{conn.request_path}"

    conn_with_target =
      Map.update!(conn, :req_headers, &[{"(request-target)", target} | &1])

    if HTTPSignatures.validate_conn(conn_with_target) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp validate_activity(%{"type" => type, "actor" => actor, "id" => id})
       when is_binary(type) and is_binary(actor) and is_binary(id),
       do: :ok

  defp validate_activity(_), do: {:error, :invalid_activity}

  defp enqueue_activity(%{"type" => "Ping"} = activity, person) do
    %{"activity" => activity, "person_id" => person.id}
    |> Revix.Workers.ProcessInboundPingWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Pong"} = activity, person) do
    %{"activity" => activity, "person_id" => person.id}
    |> Revix.Workers.ProcessInboundPongWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Follow"} = activity, person) do
    %{"activity" => activity, "person_id" => person.id}
    |> Revix.Workers.ProcessInboundFollowWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Like"} = activity, person) do
    %{"activity" => activity, "person_id" => person.id}
    |> Revix.Workers.ProcessInboundLikeWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Undo", "object" => %{"type" => "Follow"}} = activity, person) do
    %{"activity" => activity, "person_id" => person.id}
    |> Revix.Workers.ProcessInboundUndoFollowWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Undo"} = activity, person) do
    %{"activity" => activity, "person_id" => person.id}
    |> Revix.Workers.ProcessInboundUndoLikeWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Create", "object" => %{"type" => type}} = activity, person)
       when type in ["Note", "Article"] do
    %{"activity" => activity, "person_id" => person.id}
    |> Revix.Workers.ProcessInboundCreateNoteWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(_activity, _person), do: :ok
end
