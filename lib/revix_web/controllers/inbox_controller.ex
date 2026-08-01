defmodule RevixWeb.InboxController do
  use RevixWeb, :controller

  require Logger

  alias Revix.ActivityLogs
  alias Revix.Federation.SignatureVerifier
  alias Revix.People

  action_fallback RevixWeb.FallbackController

  def create(conn, %{"id" => person_id} = _params) do
    with {:ok, person} <- safe_get_local_person(person_id),
         {:ok, verified_actor_uri} <- verify_signature(conn),
         :ok <- validate_activity(conn.body_params),
         :ok <- verify_actor_match(conn.body_params, verified_actor_uri) do
      enqueued? = enqueue_and_check(conn.body_params, person)
      ActivityLogs.log_inbound(conn.body_params, enqueued?, Logger.metadata()[:request_id])
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

    with true <- HTTPSignatures.validate_conn(conn_with_target),
         {:ok, _verified_actor_uri} = ok <- SignatureVerifier.verified_key_id(conn_with_target) do
      ok
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp validate_activity(%{"type" => type, "actor" => actor, "id" => id})
       when is_binary(type) and is_binary(actor) and is_binary(id),
       do: :ok

  defp validate_activity(_), do: {:error, :invalid_activity}

  defp verify_actor_match(%{"actor" => actor}, verified_actor_uri)
       when actor == verified_actor_uri,
       do: :ok

  defp verify_actor_match(_activity, _verified_actor_uri), do: {:error, :invalid_signature}

  defp enqueue_and_check(activity, person) do
    case enqueue_activity(activity, person) do
      {:ok, _job} -> true
      :ok -> false
    end
  end

  defp enqueue_activity(%{"type" => "Ping"} = activity, person) do
    job_args(activity, person)
    |> Revix.Workers.ProcessInboundPingWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Pong"} = activity, person) do
    job_args(activity, person)
    |> Revix.Workers.ProcessInboundPongWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Follow"} = activity, person) do
    job_args(activity, person)
    |> Revix.Workers.ProcessInboundFollowWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Like"} = activity, person) do
    job_args(activity, person)
    |> Revix.Workers.ProcessInboundLikeWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Undo", "object" => %{"type" => "Follow"}} = activity, person) do
    job_args(activity, person)
    |> Revix.Workers.ProcessInboundUndoFollowWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Undo"} = activity, person) do
    job_args(activity, person)
    |> Revix.Workers.ProcessInboundUndoLikeWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Update", "object" => %{"type" => type}} = activity, person)
       when type in ["Note", "Article", "Event"] do
    job_args(activity, person)
    |> Revix.Workers.ProcessInboundUpdateNoteWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Delete"} = activity, person) do
    job_args(activity, person)
    |> Revix.Workers.ProcessInboundDeleteWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(%{"type" => "Create", "object" => %{"type" => type}} = activity, person)
       when type in ["Note", "Article", "Event"] do
    job_args(activity, person)
    |> Revix.Workers.ProcessInboundCreateNoteWorker.new()
    |> Oban.insert()
  end

  defp enqueue_activity(_activity, _person), do: :ok

  defp job_args(activity, person) do
    %{"activity" => activity, "person_id" => person.id}
  end
end
