defmodule Revix.MailerConfig do
  @moduledoc """
  Builds the `Revix.Mailer` config from SMTP environment variables.

  When `SMTP_HOST` is unset the mailer keeps its environment default (Local in
  dev, SES in prod, Test in test). When it is set, the mailer switches to
  `Swoosh.Adapters.SMTP` with the options below.

  Supported variables:

    * `SMTP_HOST` — SMTP relay hostname; its presence enables SMTP
    * `SMTP_PORT` — relay port (default: `587`)
    * `SMTP_USERNAME` / `SMTP_PASSWORD` — optional auth credentials
    * `SMTP_SSL` — connect through SSL (`"true"` or `"1"`; default: `false`)
    * `SMTP_TLS` — `never` | `always` | `if_available` (default: `if_available`)
    * `SMTP_AUTH` — `never` | `always` | `if_available` (default: `if_available`)
    * `SMTP_HOSTNAME` — FQDN sent in the EHLO greeting (default: auto-detected)
    * `SMTP_RETRIES` — delivery attempts (default: `1`)
  """

  @default_port 587

  @doc """
  Returns the SMTP mailer config keyword list when `SMTP_HOST` is set in
  `env`, otherwise `nil`.
  """
  def smtp_config(env \\ System.get_env()) do
    case env["SMTP_HOST"] do
      nil -> nil
      relay -> build_config(env, relay)
    end
  end

  defp build_config(env, relay) do
    ssl = truthy?(env["SMTP_SSL"])

    [
      adapter: Swoosh.Adapters.SMTP,
      relay: relay,
      port: parse_port(env["SMTP_PORT"]),
      ssl: ssl,
      tls: parse_enum(env["SMTP_TLS"], "SMTP_TLS"),
      auth: parse_enum(env["SMTP_AUTH"], "SMTP_AUTH"),
      # gen_smtp never verified TLS certificates; OTP 28 flipped the ssl
      # default to verify_peer, which breaks STARTTLS against servers whose
      # CA chain Erlang cannot resolve. Restore the historical behaviour.
      # Implicit TLS (ssl: true) ignores tls_options and needs the socket option.
      tls_options: [verify: :verify_none]
    ]
    |> maybe_put(:sockopts, if(ssl, do: [verify: :verify_none]))
    |> maybe_put(:username, env["SMTP_USERNAME"])
    |> maybe_put(:password, env["SMTP_PASSWORD"])
    |> maybe_put(:hostname, env["SMTP_HOSTNAME"])
    |> maybe_put(:retries, parse_retries(env["SMTP_RETRIES"]))
  end

  defp parse_port(nil), do: @default_port

  defp parse_port(value) do
    parse_int!(value, "SMTP_PORT")
  end

  defp parse_retries(nil), do: nil
  defp parse_retries(""), do: nil

  defp parse_retries(value) do
    parse_int!(value, "SMTP_RETRIES")
  end

  defp parse_int!(value, var) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> int
      _ -> raise ArgumentError, "#{var} must be a positive integer, got: #{inspect(value)}"
    end
  end

  defp parse_enum(nil, _var), do: :if_available

  defp parse_enum(value, var) do
    parse_enum_value(String.downcase(String.trim(value)), var)
  end

  defp parse_enum_value("never", _var), do: :never
  defp parse_enum_value("always", _var), do: :always
  defp parse_enum_value("if_available", _var), do: :if_available

  defp parse_enum_value(other, var) do
    raise ArgumentError,
          "#{var} must be one of never, always, if_available, got: #{inspect(other)}"
  end

  defp truthy?(nil), do: false

  defp truthy?(value), do: String.downcase(value) in ["true", "1"]

  defp maybe_put(config, _key, nil), do: config
  defp maybe_put(config, _key, ""), do: config
  defp maybe_put(config, key, value), do: Keyword.put(config, key, value)
end
