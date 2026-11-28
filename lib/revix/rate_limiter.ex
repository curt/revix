defmodule Revix.RateLimiter do
  @moduledoc """
  A fixed-window request counter kept in ETS.

  `hit/4` counts one request against `key` in the current window and says
  whether it is within `limit`. The table is owned by this process and swept
  every minute so finished windows don't accumulate. Counts live on one node
  only, which matches how Revix is deployed.

  Options for `hit/4` and `sweep/1`: `:table` (default `#{inspect(__MODULE__)}`)
  and `:now` in milliseconds (default: the system clock), so tests can control
  both.
  """
  use GenServer

  @default_sweep_every :timer.minutes(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def hit(key, limit, window_ms, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &now/0)
    bucket = {key, div(now, window_ms)}
    expires_at = (div(now, window_ms) + 1) * window_ms

    opts
    |> table()
    |> :ets.update_counter(bucket, {2, 1}, {bucket, 0, expires_at})
    |> within(limit)
  end

  def sweep(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &now/0)
    :ets.select_delete(table(opts), [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
  end

  defp within(count, limit) when count <= limit, do: :ok
  defp within(_count, _limit), do: {:error, :rate_limited}

  defp table(opts), do: Keyword.get(opts, :table, __MODULE__)
  defp now, do: System.system_time(:millisecond)

  @impl true
  def init(opts) do
    table = table(opts)
    :ets.new(table, [:named_table, :public, :set, write_concurrency: true])
    state = %{table: table, sweep_every: Keyword.get(opts, :sweep_every, @default_sweep_every)}
    schedule_sweep(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep(table: state.table)
    schedule_sweep(state)
    {:noreply, state}
  end

  defp schedule_sweep(%{sweep_every: :never}), do: :ok
  defp schedule_sweep(%{sweep_every: ms}), do: Process.send_after(self(), :sweep, ms)
end
