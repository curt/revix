defmodule Revix.Follows do
  import Ecto.Query, warn: false
  alias Revix.Repo
  alias Revix.People
  alias Revix.Follows.Follow
  alias Revix.ActivityPub.TagUri

  ## Outbound (local person follows someone)

  def follow(%Revix.People.Scope{} = scope, target_uri) when is_binary(target_uri) do
    with {:ok, person} <- People.get_or_fetch_person_by_uri(target_uri) do
      if scope.person.uri == person.uri,
        do: {:error, :self_follow},
        else: do_follow(scope.person.uri, person.uri)
    end
  end

  defp do_follow(actor_uri, target_uri) do
    actor_uri
    |> get_follow_by_pair(target_uri)
    |> insert_or_refollow(actor_uri, target_uri)
    |> tap_ok(&enqueue_deliver_follow/1)
  end

  defp insert_or_refollow(nil, actor_uri, target_uri) do
    {id, uri} = TagUri.generate("follow")

    %Follow{id: id}
    |> Follow.create_changeset(%{
      uri: uri,
      follower_uri: actor_uri,
      following_uri: target_uri,
      origin: :local
    })
    |> Repo.insert()
  end

  defp insert_or_refollow(%Follow{unfollowed_at: nil} = follow, _actor_uri, _target_uri),
    do: {:ok, follow}

  defp insert_or_refollow(%Follow{} = follow, _actor_uri, _target_uri) do
    follow |> Follow.refollow_changeset() |> Repo.update()
  end

  def unfollow(%Revix.People.Scope{} = scope, following_uri) when is_binary(following_uri) do
    with {:ok, person} <- People.get_or_fetch_person_by_uri(following_uri) do
      scope.person.uri
      |> get_active_follow(person.uri)
      |> soft_delete_follow()
      |> tap_ok(&enqueue_deliver_undo_follow/1)
    end
  end

  defp soft_delete_follow(nil), do: {:error, :not_found}

  defp soft_delete_follow(%Follow{} = follow),
    do: follow |> Follow.unfollow_changeset() |> Repo.update()

  def accept_follow(follow_id) when is_binary(follow_id) do
    Follow
    |> Repo.get(follow_id)
    |> do_accept_follow()
  end

  defp do_accept_follow(nil), do: {:error, :not_found}

  defp do_accept_follow(%Follow{} = follow),
    do: follow |> Follow.accept_changeset() |> Repo.update()

  ## Inbound (remote follows local)

  def upsert_inbound_follow(%{uri: uri, follower_uri: follower_uri, following_uri: following_uri}) do
    auto_accept = Application.get_env(:revix, :follows)[:auto_accept] != false

    (get_follow_by_uri(uri) || get_follow_by_pair(follower_uri, following_uri))
    |> upsert_follow(uri, follower_uri, following_uri, auto_accept)
    |> tap_ok(&maybe_accept_and_broadcast(&1, auto_accept))
  end

  defp upsert_follow(nil, uri, follower_uri, following_uri, auto_accept) do
    {id, _} = TagUri.generate("follow")

    %Follow{id: id}
    |> Follow.create_changeset(%{
      uri: uri,
      follower_uri: follower_uri,
      following_uri: following_uri,
      origin: :remote,
      accepted_at: accepted_at_for(auto_accept)
    })
    |> Repo.insert()
  end

  defp upsert_follow(%Follow{unfollowed_at: nil} = follow, _uri, _follower, _following, _accept),
    do: {:ok, follow}

  defp upsert_follow(%Follow{} = follow, _uri, _follower, _following, auto_accept) do
    follow
    |> Follow.refollow_changeset()
    |> Ecto.Changeset.change(accepted_at: accepted_at_for(auto_accept))
    |> Repo.update()
  end

  defp accepted_at_for(true), do: DateTime.utc_now(:second)
  defp accepted_at_for(false), do: nil

  defp maybe_accept_and_broadcast(follow, true) do
    enqueue_deliver_accept_follow(follow)
    broadcast_follow_update(follow.following_uri)
  end

  defp maybe_accept_and_broadcast(follow, false) do
    broadcast_follow_update(follow.following_uri)
  end

  def undo_inbound_follow(follow_uri) when is_binary(follow_uri) do
    Repo.one(from f in Follow, where: f.uri == ^follow_uri and is_nil(f.unfollowed_at))
    |> undo_follow()
  end

  def undo_inbound_follow(follower_uri, following_uri)
      when is_binary(follower_uri) and is_binary(following_uri) do
    get_active_follow(follower_uri, following_uri)
    |> undo_follow()
  end

  defp undo_follow(nil), do: {:error, :not_found}

  defp undo_follow(%Follow{} = follow) do
    follow
    |> Follow.unfollow_changeset()
    |> Repo.update()
    |> tap_ok(&broadcast_follow_update(&1.following_uri))
  end

  ## Queries

  def get_followers_for_person(person_uri, opts \\ []) do
    Follow
    |> where([f], f.following_uri == ^person_uri)
    |> where([f], is_nil(f.unfollowed_at))
    |> where([f], not is_nil(f.accepted_at))
    |> order_by([f], desc: f.inserted_at)
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
  end

  def get_following_for_person(person_uri, opts \\ []) do
    Follow
    |> where([f], f.follower_uri == ^person_uri)
    |> where([f], is_nil(f.unfollowed_at))
    |> order_by([f], desc: f.inserted_at)
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
  end

  def get_pending_followers_for_person(person_uri) do
    Repo.all(
      from f in Follow,
        where:
          f.following_uri == ^person_uri and
            is_nil(f.unfollowed_at) and
            is_nil(f.accepted_at),
        order_by: [desc: f.inserted_at]
    )
  end

  def followed_by_any_local?(actor_uri) when is_binary(actor_uri) do
    Repo.exists?(
      from f in Follow,
        join: p in Revix.People.Person,
        on: p.uri == f.follower_uri and p.origin == :local,
        where: f.following_uri == ^actor_uri and is_nil(f.unfollowed_at)
    )
  end

  def follower_of?(nil, _following_uri), do: false

  def follower_of?(follower_uri, following_uri) do
    Repo.exists?(
      from f in Follow,
        where:
          f.follower_uri == ^follower_uri and
            f.following_uri == ^following_uri and
            is_nil(f.unfollowed_at) and
            not is_nil(f.accepted_at)
    )
  end

  def following?(nil, _following_uri), do: false

  def following?(follower_uri, following_uri) do
    Repo.exists?(
      from f in Follow,
        where:
          f.follower_uri == ^follower_uri and
            f.following_uri == ^following_uri and
            is_nil(f.unfollowed_at)
    )
  end

  def count_followers(person_uri) do
    Repo.one(
      from f in Follow,
        where:
          f.following_uri == ^person_uri and
            is_nil(f.unfollowed_at) and
            not is_nil(f.accepted_at),
        select: count()
    )
  end

  def count_following(person_uri) do
    Repo.one(
      from f in Follow,
        where: f.follower_uri == ^person_uri and is_nil(f.unfollowed_at),
        select: count()
    )
  end

  ## PubSub

  def subscribe_to_follows(person_uri) do
    Phoenix.PubSub.subscribe(Revix.PubSub, "follows:#{person_uri}")
  end

  ## Private

  defp get_follow_by_uri(uri) do
    Repo.one(from f in Follow, where: f.uri == ^uri)
  end

  defp get_follow_by_pair(follower_uri, following_uri) do
    Repo.one(
      from f in Follow,
        where: f.follower_uri == ^follower_uri and f.following_uri == ^following_uri
    )
  end

  defp get_active_follow(follower_uri, following_uri) do
    Repo.one(
      from f in Follow,
        where:
          f.follower_uri == ^follower_uri and
            f.following_uri == ^following_uri and
            is_nil(f.unfollowed_at)
    )
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) when is_integer(limit), do: limit(query, ^limit)

  defp broadcast_follow_update(person_uri) do
    Phoenix.PubSub.broadcast(Revix.PubSub, "follows:#{person_uri}", :follows_updated)
  end

  defp enqueue_deliver_follow(follow) do
    %{"follow_id" => follow.id}
    |> Revix.Workers.DeliverFollowWorker.new()
    |> Oban.insert()
  end

  defp enqueue_deliver_undo_follow(follow) do
    %{"follow_id" => follow.id}
    |> Revix.Workers.DeliverUndoFollowWorker.new()
    |> Oban.insert()
  end

  defp enqueue_deliver_accept_follow(follow) do
    %{"follow_id" => follow.id}
    |> Revix.Workers.DeliverAcceptFollowWorker.new()
    |> Oban.insert()
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(result, _fun), do: result
end
