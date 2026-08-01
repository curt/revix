defmodule Revix.Workers.InboundFollowResponseHelpers do
  def perform(activity, resolve_fun) do
    actor_uri = activity["actor"]
    follow_uri = extract_follow_uri(activity["object"])

    with uri when is_binary(uri) <- follow_uri,
         actor when is_binary(actor) <- actor_uri do
      dispatch(resolve_fun, uri, actor)
    else
      _ -> {:error, :invalid_activity}
    end
  end

  defp dispatch(resolve_fun, uri, actor_uri) do
    case resolve_fun.(uri, actor_uri) do
      {:ok, _follow} -> :ok
      {:error, :not_found} -> :ok
      {:error, :actor_mismatch} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_follow_uri(%{"id" => id}) when is_binary(id), do: id
  defp extract_follow_uri(_), do: nil
end
