defmodule Revix.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Revix.RateLimiter

  @window 60_000

  setup context do
    table = :"rate_limiter_#{context.test}"
    start_supervised!({RateLimiter, name: table, table: table, sweep_every: :never})
    %{table: table}
  end

  defp hit(key, now, table), do: RateLimiter.hit(key, 3, @window, table: table, now: now)

  test "allows up to the limit within a window, then rejects", %{table: t} do
    assert hit("a", 1_000, t) == :ok
    assert hit("a", 2_000, t) == :ok
    assert hit("a", 3_000, t) == :ok
    assert hit("a", 4_000, t) == {:error, :rate_limited}
    assert hit("a", 59_999, t) == {:error, :rate_limited}
  end

  test "starts counting again in the next window", %{table: t} do
    for now <- [1_000, 2_000, 3_000], do: hit("a", now, t)
    assert hit("a", 59_999, t) == {:error, :rate_limited}
    assert hit("a", 60_000, t) == :ok
  end

  test "counts each key separately", %{table: t} do
    for now <- [1_000, 2_000, 3_000], do: hit("a", now, t)
    assert hit("b", 4_000, t) == :ok
  end

  test "sweep removes only buckets whose window has ended", %{table: t} do
    hit("old", 1_000, t)
    hit("current", 61_000, t)

    assert RateLimiter.sweep(table: t, now: 61_000) == 1
    assert RateLimiter.sweep(table: t, now: 61_000) == 0
    assert RateLimiter.sweep(table: t, now: 120_000) == 1
  end

  test "sweeps periodically on its own" do
    table = :rate_limiter_periodic
    start_supervised!({RateLimiter, name: table, table: table, sweep_every: 10}, id: :periodic)
    RateLimiter.hit("old", 1, 1, table: table, now: 0)

    Process.sleep(50)
    assert :ets.tab2list(table) == []

    # and keeps sweeping, not just once
    RateLimiter.hit("later", 1, 1, table: table, now: 0)
    Process.sleep(50)
    assert :ets.tab2list(table) == []
  end

  test "the application starts the default limiter" do
    assert RateLimiter.hit("default-#{System.unique_integer()}", 1, @window) == :ok
  end
end
