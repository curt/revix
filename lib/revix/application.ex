defmodule Revix.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    with :ok <-
           Revix.MailerProbe.startup_check(Application.get_env(:revix, :mailer_startup_check)) do
      start_supervisor()
    end
  end

  defp start_supervisor do
    children = [
      RevixWeb.Telemetry,
      Revix.Repo,
      {DNSCluster, query: Application.get_env(:revix, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Revix.PubSub},
      Revix.Vault,
      Revix.RateLimiter,
      {Oban, Application.fetch_env!(:revix, Oban)},
      RevixWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Revix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RevixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
