defmodule Revix.Notifications do
  @moduledoc """
  Subscriber email notifications.

  Every local person with a verified email (`origin: :local`, `confirmed_at` set)
  is a subscriber. Their `notification_schedule` (`:hourly | :daily | :weekly |
  :none`, default `:daily`) controls how often a digest is delivered.

  Events are captured at emit time as `Notification` rows (write-on-emit); a
  per-cadence Oban cron job batches each subscriber's unsent rows into one digest
  email. The emit helpers are best-effort and never raise, so a notification
  failure cannot break entry/like creation.
  """

  import Ecto.Query

  require Logger

  alias Revix.EntryPeople
  alias Revix.Entries.Entry
  alias Revix.Follows
  alias Revix.Likes
  alias Revix.Likes.Like
  alias Revix.Notifications.DigestNotifier
  alias Revix.Notifications.Notification
  alias Revix.People.Person
  alias Revix.Places.Place
  alias Revix.Repo
  alias Revix.Snippet

  @behaviour Revix.Notifications.Behaviour

  @summary_max 140
  @default_ancestor_depth_limit 20
  @default_send_offset_minutes 30

  ## Preferences

  @doc "Returns the person's current notification cadence."
  def get_schedule(%Person{notification_schedule: schedule}), do: schedule

  @doc """
  Sets the person's notification cadence. Mirrors `Revix.People.set_person_role/2`.
  """
  def set_schedule(%Person{} = person, schedule) when is_atom(schedule) do
    person
    |> Person.notification_changeset(%{notification_schedule: schedule})
    |> Repo.update()
  end

  @doc """
  Options for a cadence `<select>`, kept in sync with the Ecto type.
  """
  def schedule_options do
    labels = %{
      hourly: "Hourly",
      daily: "Daily",
      weekly: "Weekly",
      monthly: "Monthly",
      none: "Off"
    }

    Enum.map(Revix.Ecto.NotificationSchedule.values(), &{Map.fetch!(labels, &1), &1})
  end

  ## Emit

  @impl true
  def notify_new_entry(%Entry{} = entry) do
    entry = Repo.preload(entry, :author)
    recipients = new_entry_recipients(entry)

    Enum.each(recipients, fn {recipient_uri, type} ->
      emit(
        recipient_uri,
        type,
        entry.uri,
        entry.author_uri,
        new_entry_summary(type, entry),
        entry.url
      )
    end)

    :ok
  end

  @impl true
  def notify_like(%Like{} = like) do
    recipients =
      like.object_uri
      |> ancestor_chain()
      |> ancestor_authors()
      |> Enum.reject(&(&1 == like.author_uri))
      |> eligible_recipient_uris()

    summary = actor_summary(like.author_uri, "liked a post in a conversation you're part of")

    Enum.each(recipients, fn recipient_uri ->
      # Subject is the liked object, not the Like activity: a recipient gets one
      # row per post, however many people like it.
      emit(
        recipient_uri,
        :like,
        like.object_uri,
        like.author_uri,
        summary,
        entry_url(like.object_uri)
      )
    end)

    :ok
  end

  @impl true
  def notify_reply(%Entry{} = note) do
    chain = ancestor_chain(note.in_reply_to_uri)

    recipients =
      (ancestor_authors(chain) ++ root_companion_uris(chain) ++ thread_liker_uris(chain))
      |> Enum.uniq()
      |> Enum.reject(&(&1 == note.author_uri))
      |> eligible_recipient_uris()

    summary = actor_summary(note.author_uri, "commented in a conversation you're part of")

    Enum.each(recipients, fn recipient_uri ->
      emit(recipient_uri, :reply, note.uri, note.author_uri, summary, note.url)
    end)

    :ok
  end

  @impl true
  def notify_registration(%Person{} = new_person) do
    recipients =
      owner_uris()
      |> Enum.reject(&(&1 == new_person.uri))
      |> eligible_recipient_uris()

    summary = "#{display_name(new_person)} joined"

    Enum.each(recipients, fn recipient_uri ->
      emit(recipient_uri, :registration, new_person.uri, new_person.uri, summary, new_person.url)
    end)

    :ok
  end

  # Low-level: insert one row, idempotent on (recipient, type, subject). Never raises.
  defp emit(recipient_uri, type, subject_uri, actor_uri, summary, url) do
    %Notification{}
    |> Notification.create_changeset(%{
      recipient_uri: recipient_uri,
      type: type,
      subject_uri: subject_uri,
      actor_uri: actor_uri,
      summary: summary,
      url: url
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:recipient_uri, :type, :subject_uri]
    )
    |> case do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.warning(
          "notification emit failed: type=#{type} recipient=#{recipient_uri} " <>
            "subject=#{subject_uri} errors=#{inspect(changeset.errors)}"
        )

        :ok
    end
  rescue
    error ->
      Logger.warning(
        "notification emit crashed: type=#{type} recipient=#{recipient_uri} " <>
          "subject=#{subject_uri} #{Exception.message(error)}"
      )

      :ok
  end

  ## Recipient resolution

  defp new_entry_recipients(%Entry{} = entry) do
    owner = owner_entry_recipients(entry)
    owner_set = MapSet.new(owner, fn {uri, _type} -> uri end)

    followed =
      entry
      |> followed_entry_recipients()
      |> Enum.reject(fn {uri, _type} -> MapSet.member?(owner_set, uri) end)

    owner ++ followed
  end

  defp owner_entry_recipients(%Entry{author: %Person{role: :owner, origin: :local}} = entry)
       when entry.type in [:post, :checkin] do
    case entry.published_at_utc do
      nil ->
        []

      _ ->
        for uri <- eligible_recipient_uris(all_subscriber_uris(entry.author_uri)),
            do: {uri, :owner_entry}
    end
  end

  defp owner_entry_recipients(_entry), do: []

  defp followed_entry_recipients(%Entry{} = entry) do
    follower_uris =
      entry.author_uri
      |> Follows.get_followers_for_person()
      |> Enum.map(& &1.follower_uri)
      |> Enum.reject(&(&1 == entry.author_uri))

    for uri <- eligible_recipient_uris(follower_uris), do: {uri, :followed_entry}
  end

  # All local confirmed subscribers except `except_uri`; caller passes through
  # `eligible_recipient_uris/1` for the `:none` filter.
  defp all_subscriber_uris(except_uri) do
    Repo.all(
      from p in Person,
        where: p.origin == :local and not is_nil(p.confirmed_at) and p.uri != ^except_uri,
        select: p.uri
    )
  end

  defp owner_uris do
    Repo.all(
      from p in Person,
        where: p.origin == :local and p.role == :owner,
        select: p.uri
    )
  end

  # One query: keep only local, confirmed, opted-in recipients.
  defp eligible_recipient_uris([]), do: []

  defp eligible_recipient_uris(candidate_uris) do
    uris = Enum.uniq(candidate_uris)

    Repo.all(
      from p in Person,
        where:
          p.uri in ^uris and p.origin == :local and not is_nil(p.confirmed_at) and
            p.notification_schedule != :none,
        select: p.uri
    )
  end

  # Walk `in_reply_to_uri` from `entry_uri` up to the root, returning
  # `[{uri, author_uri}, ...]` ordered from the given entry to the root.
  defp ancestor_chain(nil), do: []
  defp ancestor_chain(entry_uri), do: ancestor_chain(entry_uri, 0, [])

  defp ancestor_chain(nil, _depth, acc), do: Enum.reverse(acc)

  defp ancestor_chain(uri, depth, acc) do
    if depth >= ancestor_depth_limit() do
      Enum.reverse(acc)
    else
      case Repo.one(
             from e in Entry,
               where: e.uri == ^uri,
               select: {e.uri, e.author_uri, e.in_reply_to_uri}
           ) do
        nil ->
          Enum.reverse(acc)

        {self_uri, author_uri, parent_uri} ->
          ancestor_chain(parent_uri, depth + 1, [{self_uri, author_uri} | acc])
      end
    end
  end

  defp ancestor_authors(chain), do: chain |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

  # Companions tagged on the root entry of the thread.
  defp root_companion_uris([]), do: []

  defp root_companion_uris(chain) do
    {root_uri, _author_uri} = List.last(chain)
    root_uri |> EntryPeople.get_companions_for_entry() |> Enum.map(& &1.person_uri)
  end

  # Local people who liked any entry in the thread — an interaction that also
  # earns them notifications about subsequent comments.
  defp thread_liker_uris([]), do: []

  defp thread_liker_uris(chain) do
    chain |> Enum.map(&elem(&1, 0)) |> Likes.liker_uris_for_objects()
  end

  defp ancestor_depth_limit do
    Application.get_env(:revix, :notification_ancestor_depth_limit, @default_ancestor_depth_limit)
  end

  ## Summaries (frozen at emit time)

  defp new_entry_summary(:owner_entry, %Entry{} = entry),
    do: "#{entry_author_name(entry)} published a #{entry_noun(entry)}#{entry_snippet(entry)}"

  defp new_entry_summary(:followed_entry, %Entry{} = entry),
    do: "#{entry_author_name(entry)} posted a #{entry_noun(entry)}#{entry_snippet(entry)}"

  defp actor_summary(actor_uri, verb_phrase),
    do: "#{display_name_by_uri(actor_uri)} #{verb_phrase}"

  # notify_new_entry only fires for :post and :checkin.
  defp entry_noun(%Entry{type: :checkin}), do: "checkin"
  defp entry_noun(%Entry{type: :post}), do: "post"

  # ": <place> — <title> — <body excerpt>" — each part included only when present.
  defp entry_snippet(%Entry{} = entry) do
    case Enum.reject(
           [entry_place_name(entry), entry_title(entry), entry_body_excerpt(entry)],
           &is_nil/1
         ) do
      [] -> ""
      parts -> ": " <> Enum.join(parts, " — ")
    end
  end

  defp entry_place_name(%Entry{type: :checkin, place_uri: uri}) when is_binary(uri) do
    case Repo.one(from p in Place, where: p.uri == ^uri, select: p.name) do
      name when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  defp entry_place_name(_entry), do: nil

  defp entry_title(%Entry{name: name}) when is_binary(name) and name != "", do: name
  defp entry_title(_entry), do: nil

  defp entry_body_excerpt(%Entry{content: content}) when is_binary(content) and content != "" do
    case Snippet.snippify(content, @summary_max) do
      "" -> nil
      snippet -> snippet
    end
  end

  defp entry_body_excerpt(_entry), do: nil

  defp entry_author_name(%Entry{author: %Person{} = author}), do: display_name(author)
  defp entry_author_name(%Entry{author_uri: uri}), do: display_name_by_uri(uri)

  defp display_name(%Person{display_name: name}) when is_binary(name) and name != "", do: name

  defp display_name(%Person{username: username}) when is_binary(username) and username != "",
    do: username

  defp display_name(%Person{uri: uri}), do: uri

  defp display_name_by_uri(nil), do: "Someone"

  defp display_name_by_uri(uri) do
    case Repo.one(from p in Person, where: p.uri == ^uri) do
      nil -> uri
      person -> display_name(person)
    end
  end

  # The liked object always exists here (a recipient is only produced when
  # `ancestor_chain/1` resolves it), and `entries.url` is NOT NULL.
  defp entry_url(entry_uri) do
    Repo.one(from e in Entry, where: e.uri == ^entry_uri, select: e.url) || entry_uri
  end

  ## Digest send

  @doc """
  Builds and delivers one digest email per subscriber on `schedule` who has
  unsent notifications older than the send offset. Stamps `sent_at` on delivery.

  `deps` accepts:
    * `:notifier` - module with `build/3` (default `DigestNotifier`)
    * `:mailer` - module with `deliver/1` (default `Revix.Mailer`)
    * `:settings_url` - absolute URL to the notification settings page
    * `:site_title` - display name for the subject line
    * `:send_offset_minutes` - override the configured settling lag
      (`config :revix, :notifications, send_offset_minutes:`)
  """
  def deliver_digests(schedule, now \\ DateTime.utc_now(), deps \\ []) when is_atom(schedule) do
    notifier = Keyword.get(deps, :notifier, DigestNotifier)
    mailer = Keyword.get(deps, :mailer, Revix.Mailer)
    offset = Keyword.get(deps, :send_offset_minutes, send_offset_minutes())
    cutoff = DateTime.add(now, -offset, :minute)

    schedule
    |> subscribers_for_schedule()
    |> Enum.reduce(%{sent: 0, skipped: 0}, fn subscriber, acc ->
      deliver_one(
        subscriber,
        pending_for(subscriber.uri, cutoff),
        now,
        notifier,
        mailer,
        deps,
        acc
      )
    end)
  end

  defp deliver_one(_subscriber, [], _now, _notifier, _mailer, _deps, acc),
    do: %{acc | skipped: acc.skipped + 1}

  defp deliver_one(subscriber, pending, now, notifier, mailer, deps, acc) do
    email = notifier.build(subscriber, dedupe_by_subject(pending), run_context(now, deps))

    case mailer.deliver(email) do
      {:ok, _} ->
        # Stamp every pending row, including any collapsed by dedupe, so a
        # subject never resurfaces in a later digest.
        stamp_sent(Enum.map(pending, & &1.id), now)
        %{acc | sent: acc.sent + 1}

      other ->
        log_digest_failure(subscriber.uri, length(pending), other)
        %{acc | skipped: acc.skipped + 1}
    end
  rescue
    # One subscriber's digest crashing (bad build, DB blip mid-stamp) must not
    # abort the batch and force Oban to re-send to everyone already delivered.
    error ->
      log_digest_failure(subscriber.uri, length(pending), error)
      %{acc | skipped: acc.skipped + 1}
  end

  defp log_digest_failure(recipient_uri, deferred, reason) do
    Logger.warning(
      "notification digest delivery failed: recipient=#{recipient_uri} " <>
        "deferred=#{deferred} #{inspect(reason)}"
    )
  end

  # A single post/checkin/like/comment must appear at most once per digest, even
  # if two emit paths produced rows about it (e.g. a followed owner's post).
  # Keep the highest-priority row per subject_uri; preserve inserted_at order.
  defp dedupe_by_subject(notifications) do
    notifications
    |> Enum.group_by(& &1.subject_uri)
    |> Enum.map(fn {_subject, rows} -> Enum.min_by(rows, &type_priority(&1.type)) end)
    |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})
  end

  defp type_priority(:owner_entry), do: 0
  defp type_priority(:followed_entry), do: 1
  defp type_priority(:reply), do: 2
  defp type_priority(:like), do: 3
  defp type_priority(:registration), do: 4

  defp run_context(now, deps) do
    %{
      run_at: now,
      settings_url: Keyword.get(deps, :settings_url),
      site_title: Keyword.get(deps, :site_title, "Revix")
    }
  end

  defp subscribers_for_schedule(schedule) do
    Repo.all(
      from p in Person,
        where:
          p.origin == :local and not is_nil(p.confirmed_at) and
            p.notification_schedule == ^schedule
    )
  end

  defp pending_for(recipient_uri, cutoff) do
    Repo.all(
      from n in Notification,
        where:
          n.recipient_uri == ^recipient_uri and is_nil(n.sent_at) and
            n.inserted_at <= ^cutoff,
        order_by: [asc: n.inserted_at]
    )
  end

  defp stamp_sent(ids, now) do
    Repo.update_all(from(n in Notification, where: n.id in ^ids), set: [sent_at: now])
    :ok
  end

  defp send_offset_minutes do
    Application.get_env(:revix, :notifications)[:send_offset_minutes] ||
      @default_send_offset_minutes
  end

  ## Maintenance

  @doc """
  Deletes notifications delivered more than `hours` ago. Returns `{:ok, count}`.
  """
  def purge_sent_older_than_hours(hours) when is_integer(hours) and hours > 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

    {count, _} =
      Repo.delete_all(
        from n in Notification, where: not is_nil(n.sent_at) and n.sent_at < ^cutoff
      )

    {:ok, count}
  end
end
