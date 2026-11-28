defmodule Revix.MailerConfig do
  @moduledoc """
  Builds the `Revix.Mailer` config from SMTP environment variables.

  When `SMTP_HOST` is unset or blank the mailer keeps its environment default
  (Local in dev, SES in prod, Test in test). When it is set, the mailer switches
  to `Swoosh.Adapters.SMTP` with the options below. Blank values are treated as
  unset.

  Supported variables:

    * `SMTP_HOST` — SMTP relay hostname; its presence enables SMTP
    * `SMTP_PORT` — relay port (default: `587`)
    * `SMTP_USERNAME` / `SMTP_PASSWORD` — optional auth credentials
    * `SMTP_SSL` — connect through SSL (`"true"` or `"1"`; default: `false`)
    * `SMTP_TLS` — `never` | `always` | `if_available` (default: `always` when
      `SMTP_USERNAME` is set, otherwise `if_available`)
    * `SMTP_TLS_VERIFY` — verify the relay's TLS certificate against the OS CA
      store (default: `true`; `"false"` or `"0"` to disable)
    * `SMTP_AUTH` — `never` | `always` | `if_available` (default: `if_available`)
    * `SMTP_HOSTNAME` — FQDN sent in the EHLO greeting (default: auto-detected)
    * `SMTP_RETRIES` — delivery attempts (default: `1`)
    * `SMTP_STARTUP_CHECK` — `"true"` or `"1"` to probe the relay at boot and
      abort startup when the probe fails (default: off)
  """

  @default_port 587

  @doc """
  Returns the SMTP mailer config keyword list when `SMTP_HOST` is set in
  `env`, otherwise `nil`.
  """
  def smtp_config(env \\ System.get_env()) do
    env
    |> env_value("SMTP_HOST")
    |> config_for_relay(env)
  end

  @doc """
  Returns `true` when `SMTP_STARTUP_CHECK` in `env` is truthy, enabling the
  boot-time relay probe in `Revix.MailerProbe.startup_check/1`.
  """
  def startup_check?(env \\ System.get_env()) do
    env
    |> env_value("SMTP_STARTUP_CHECK")
    |> truthy?()
  end

  @doc """
  Returns `true` for `"true"` or `"1"`, ignoring case and surrounding
  whitespace; `false` for anything else, including `nil`.
  """
  def truthy?(nil), do: false
  def truthy?(value), do: String.downcase(String.trim(value)) in ["true", "1"]

  defp config_for_relay(nil, _env), do: nil
  defp config_for_relay(relay, env), do: build_config(env, relay)

  defp build_config(env, relay) do
    ssl = truthy?(env_value(env, "SMTP_SSL"))
    username = env_value(env, "SMTP_USERNAME")
    tls_options = tls_options(relay, verify_tls?(env_value(env, "SMTP_TLS_VERIFY")))

    [
      adapter: Swoosh.Adapters.SMTP,
      relay: relay,
      port: parse_port(env_value(env, "SMTP_PORT")),
      ssl: ssl,
      tls: parse_tls(env_value(env, "SMTP_TLS"), username),
      auth: parse_enum(env_value(env, "SMTP_AUTH"), "SMTP_AUTH"),
      # STARTTLS takes its options from tls_options; implicit TLS (ssl: true)
      # ignores them and needs the same options as socket options.
      tls_options: tls_options
    ]
    |> maybe_put(:sockopts, ssl_sockopts(ssl, tls_options))
    |> maybe_put(:username, username)
    |> maybe_put(:password, secret_value(env, "SMTP_PASSWORD"))
    |> maybe_put(:hostname, env_value(env, "SMTP_HOSTNAME"))
    |> maybe_put(:retries, parse_retries(env_value(env, "SMTP_RETRIES")))
  end

  # Trimmed value of `key`, or nil when unset or blank.
  defp env_value(env, key), do: env |> Map.get(key) |> trim_blank()

  defp trim_blank(nil), do: nil
  defp trim_blank(value), do: value |> String.trim() |> blank_to_nil()

  # Secrets keep surrounding whitespace; only a blank value counts as unset.
  defp secret_value(env, key), do: env |> Map.get(key) |> keep_unless_blank()

  defp keep_unless_blank(nil), do: nil
  defp keep_unless_blank(value), do: keep_unless_blank(value, String.trim(value))

  defp keep_unless_blank(_value, ""), do: nil
  defp keep_unless_blank(value, _trimmed), do: value

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_port(nil), do: @default_port
  defp parse_port(value), do: parse_int!(value, "SMTP_PORT")

  defp parse_retries(nil), do: nil
  defp parse_retries(value), do: parse_int!(value, "SMTP_RETRIES")

  defp parse_int!(value, var), do: value |> Integer.parse() |> positive_int!(value, var)

  defp positive_int!({int, ""}, _value, _var) when int > 0, do: int

  defp positive_int!(_parsed, value, var) do
    raise ArgumentError, "#{var} must be a positive integer, got: #{inspect(value)}"
  end

  # Verify the relay certificate against the OS CA store unless
  # SMTP_TLS_VERIFY is explicitly falsy (for self-signed or internal relays).
  defp verify_tls?(nil), do: true
  defp verify_tls?(value), do: String.downcase(value) not in ["false", "0"]

  defp tls_options(relay, true) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: to_charlist(relay),
      depth: 4,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  defp tls_options(_relay, false), do: [verify: :verify_none]

  defp ssl_sockopts(true, tls_options), do: tls_options
  defp ssl_sockopts(false, _tls_options), do: nil

  # With credentials and no explicit mode, require STARTTLS so AUTH is never
  # sent in plaintext when a relay (or an attacker) omits STARTTLS.
  defp parse_tls(nil, nil), do: :if_available
  defp parse_tls(nil, _username), do: :always
  defp parse_tls(value, _username), do: parse_enum(value, "SMTP_TLS")

  defp parse_enum(nil, _var), do: :if_available
  defp parse_enum(value, var), do: parse_enum_value(String.downcase(value), var)

  defp parse_enum_value("never", _var), do: :never
  defp parse_enum_value("always", _var), do: :always
  defp parse_enum_value("if_available", _var), do: :if_available

  defp parse_enum_value(other, var) do
    raise ArgumentError,
          "#{var} must be one of never, always, if_available, got: #{inspect(other)}"
  end

  defp maybe_put(config, _key, nil), do: config
  defp maybe_put(config, key, value), do: Keyword.put(config, key, value)
end
