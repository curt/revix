defmodule Revix.Repo do
  use Ecto.Repo,
    otp_app: :revix,
    adapter: Ecto.Adapters.Postgres
end
