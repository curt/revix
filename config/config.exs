# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :revix, :scopes,
  person: [
    default: true,
    module: Revix.People.Scope,
    assign_key: :current_scope,
    access_path: [:person, :id],
    schema_key: :person_id,
    schema_type: :id,
    schema_table: :people,
    test_data_fixture: Revix.PeopleFixtures,
    test_setup_helper: :register_and_log_in_person
  ]

config :revix, :person, display_name_max_length: 20

config :revix, :home, activity_limit: 50

config :revix, :entry, comment_max_length: 2000

config :revix, :places, nearby_result_limit: 20

config :revix,
  ecto_repos: [Revix.Repo],
  generators: [timestamp_type: :utc_datetime]

config :revix, Revix.Repo, types: Revix.Ecto.PostgresTypes

# Configure the endpoint
config :revix, RevixWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RevixWeb.ErrorHTML, json: RevixWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Revix.PubSub,
  live_view: [signing_salt: "gZvW0pbN"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :revix, Revix.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  revix: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --loader:.png=file --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  revix: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure MIME types for ActivityPub and other JSON formats
config :mime, :types, %{
  "application/activity+json" => ["activity"],
  "application/ld+json" => ["activity"],
  "application/geo+json" => ["geo"],
  "application/atom+xml" => ["atom"]
}

config :mime, :extensions, %{
  "activity" => "application/activity+json",
  "atom" => "application/atom+xml"
}

config :waffle,
  storage: Waffle.Storage.Local,
  storage_dir_prefix: "priv/waffle/public"

config :ex_aws,
  json_codec: Jason,
  region: {:system, "AWS_REGION"},
  access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
  secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"}

# any configurations provided by https://github.com/ex-aws/ex_aws

# Use tzdata for timezone lookups (required by Timex)
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
