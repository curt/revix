import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :revix, Revix.Repo,
  username: "revix",
  password: System.get_env("POSTGRES_PASSWORD", "revix"),
  hostname: "localhost",
  port: System.get_env("POSTGRES_PORT"),
  database: "revix_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :revix, RevixWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "b5lwX7oSyOM9/PQlqxUfZn6/wfIyctI5qjDW7CfA3eBd/cMMdRiS3iZSDn5Mkmld",
  server: false

config :revix, :sql_sandbox, true

# In test we don't send emails
config :revix, Revix.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Stub Overpass HTTP calls in tests via Req.Test
config :revix, :overpass_req_plug, {Req.Test, :overpass}

# Stub federation HTTP calls in tests via Req.Test
config :revix, :federation_req_plug, {Req.Test, :federation}

# Stub inbound attachment downloads in tests via Req.Test
config :revix, :inbound_attachment_req_plug, {Req.Test, :inbound_attachment}

# Use manual testing mode for Oban — jobs are enqueued but never auto-executed.
# Use perform_job/2 (via Oban.Testing) to run specific workers in tests.
config :revix, Oban, testing: :manual

# Fixed test-only key for Cloak vault (no CLOAK_KEY env var needed in test)
config :revix, Revix.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("a9KFQ/0sX7+VUMTqfECbNlp8e3GAXGZ8OqnOV8rQxDI=")}
  ]
