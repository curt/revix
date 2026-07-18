defmodule RevixWeb.CreditsController do
  use RevixWeb, :controller

  alias RevixWeb.CanonicalRoutes
  alias RevixWeb.StructuredData

  def index(conn, _params) do
    memory = :erlang.memory()
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    diagnostics = %{
      revix_version: Application.spec(:revix, :vsn),
      phoenix_version: Application.spec(:phoenix, :vsn),
      elixir_version: System.version(),
      otp_version: :erlang.system_info(:otp_release) |> List.to_string(),
      system_architecture: :erlang.system_info(:system_architecture) |> List.to_string(),
      schedulers: :erlang.system_info(:schedulers_online),
      uptime_seconds: div(uptime_ms, 1000),
      memory_total: memory[:total],
      memory_processes: memory[:processes],
      memory_atoms: memory[:atom],
      memory_ets: memory[:ets]
    }

    conn
    |> assign(:head_links, [%{rel: "canonical", href: CanonicalRoutes.credits_url()}])
    |> assign(:head_meta, StructuredData.credits_og())
    |> render(:index,
      diagnostics: diagnostics,
      page_title: "Credits · Revix",
      meta_description: "Version and system diagnostics for Revix."
    )
  end
end
