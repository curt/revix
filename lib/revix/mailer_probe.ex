defmodule Revix.MailerProbe do
  @moduledoc """
  Verifies the SMTP relay by opening (and immediately closing) a session with
  `gen_smtp` — the same library path `Swoosh.Adapters.SMTP` uses to deliver
  mail. The connect → EHLO → STARTTLS → AUTH handshake is exercised without
  sending any mail.

  `startup_check/2` runs the probe from `Revix.Application.start/2` when
  `SMTP_STARTUP_CHECK` is enabled (see `Revix.MailerConfig.startup_check?/1`),
  so a misconfigured relay aborts the boot instead of failing on the first
  outbound email. Migrations only load the application, so they never probe.
  """

  alias Revix.MailerConfig

  # gen_smtp bounds the TCP connect but waits up to 20 minutes for each reply,
  # so the whole probe runs under its own deadline.
  @default_probe_timeout 15_000
  @default_connect_timeout 5_000

  @doc """
  Runs `check_fn` (default: `check/1`) against `smtp_opts` when the startup
  check is enabled. `nil` means it is disabled and returns `:ok` without
  probing; a failed probe returns `{:error, {:smtp_startup_check_failed, reason}}`.
  """
  def startup_check(smtp_opts, check_fn \\ &check/1)

  def startup_check(nil, _check_fn), do: :ok

  def startup_check(smtp_opts, check_fn) do
    smtp_opts
    |> check_fn.()
    |> startup_result()
  end

  defp startup_result(:ok), do: :ok
  defp startup_result(error), do: {:error, {:smtp_startup_check_failed, error}}

  @doc """
  Returns `:ok` when a session can be opened, `{:error, :timeout}` when the
  relay does not finish the handshake within `:probe_timeout` ms (default
  15 s), or an error tuple from `gen_smtp` otherwise.

  `opts` is the SMTP keyword config built by `Revix.MailerConfig`; when not
  given it is read from the current environment configuration.
  """
  def check(opts \\ nil) do
    opts = opts || MailerConfig.smtp_config() || []
    open_relay(Keyword.get(opts, :relay), opts)
  end

  defp open_relay(nil, _opts), do: {:error, :relay_not_configured}

  defp open_relay(_relay, opts) do
    {probe_timeout, opts} = Keyword.pop(opts, :probe_timeout, @default_probe_timeout)

    opts
    |> Keyword.delete(:adapter)
    |> Keyword.put_new(:timeout, @default_connect_timeout)
    |> open_with_deadline(probe_timeout)
  end

  defp open_with_deadline(opts, probe_timeout) do
    task = Task.async(fn -> open(opts) end)

    task
    |> Task.yield(probe_timeout)
    |> shutdown_if_pending(task)
    |> task_result()
  end

  defp shutdown_if_pending(nil, task), do: Task.shutdown(task, :brutal_kill)
  defp shutdown_if_pending(reply, _task), do: reply

  defp task_result({:ok, result}), do: result
  defp task_result(nil), do: {:error, :timeout}

  defp open(opts) do
    with {:ok, _apps} <- Application.ensure_all_started(:ssl),
         {:ok, session} <- :gen_smtp_client.open(opts) do
      _ = :gen_smtp_client.close(session)
      :ok
    end
  end
end
