defmodule Revix.Follows.Behaviour do
  alias Revix.Follows.Follow

  @callback undo_inbound_follow(follow_uri :: String.t()) ::
              {:ok, Follow.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}

  @callback undo_inbound_follow(follower_uri :: String.t(), following_uri :: String.t()) ::
              {:ok, Follow.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
end
