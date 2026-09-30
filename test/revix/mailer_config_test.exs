defmodule Revix.MailerConfigTest do
  use ExUnit.Case, async: true

  alias Revix.MailerConfig

  describe "smtp_config/1" do
    test "returns nil when SMTP_HOST is unset" do
      assert MailerConfig.smtp_config(%{}) == nil
    end

    test "builds the SMTP config with defaults from the relay host" do
      assert MailerConfig.smtp_config(%{"SMTP_HOST" => "smtp.example.com"}) ==
               [
                 adapter: Swoosh.Adapters.SMTP,
                 relay: "smtp.example.com",
                 port: 587,
                 ssl: false,
                 tls: :if_available,
                 auth: :if_available,
                 tls_options: [verify: :verify_none]
               ]
    end

    test "defaults to the process environment" do
      assert MailerConfig.smtp_config() == MailerConfig.smtp_config(System.get_env())
    end

    test "parses a custom port" do
      config =
        MailerConfig.smtp_config(%{"SMTP_HOST" => "smtp.example.com", "SMTP_PORT" => "2525"})

      assert config[:port] == 2525
    end

    test "rejects an invalid port" do
      for value <- ["abc", "0", "-5", "587foo"] do
        assert_raise ArgumentError, ~r/SMTP_PORT must be a positive integer/, fn ->
          MailerConfig.smtp_config(%{"SMTP_HOST" => "smtp.example.com", "SMTP_PORT" => value})
        end
      end
    end

    test "includes auth credentials when set" do
      config =
        MailerConfig.smtp_config(%{
          "SMTP_HOST" => "smtp.example.com",
          "SMTP_USERNAME" => "mailer",
          "SMTP_PASSWORD" => "secret"
        })

      assert config[:username] == "mailer"
      assert config[:password] == "secret"
    end

    test "omits empty auth credentials" do
      config =
        MailerConfig.smtp_config(%{
          "SMTP_HOST" => "smtp.example.com",
          "SMTP_USERNAME" => "",
          "SMTP_PASSWORD" => ""
        })

      refute Keyword.has_key?(config, :username)
      refute Keyword.has_key?(config, :password)
    end

    test "enables SSL for truthy values" do
      for value <- ["true", "1", "TRUE"] do
        config =
          MailerConfig.smtp_config(%{"SMTP_HOST" => "smtp.example.com", "SMTP_SSL" => value})

        assert config[:ssl] == true
        assert config[:sockopts] == [verify: :verify_none]
      end
    end

    test "leaves SSL off for other values" do
      for value <- ["false", "0", "yes", ""] do
        config =
          MailerConfig.smtp_config(%{"SMTP_HOST" => "smtp.example.com", "SMTP_SSL" => value})

        assert config[:ssl] == false
        refute Keyword.has_key?(config, :sockopts)
      end
    end

    test "parses TLS modes case-insensitively" do
      for {value, expected} <- [
            {"never", :never},
            {"always", :always},
            {"IF_AVAILABLE", :if_available}
          ] do
        config =
          MailerConfig.smtp_config(%{"SMTP_HOST" => "smtp.example.com", "SMTP_TLS" => value})

        assert config[:tls] == expected
      end
    end

    test "rejects an invalid TLS mode" do
      assert_raise ArgumentError, ~r/SMTP_TLS must be one of never, always, if_available/, fn ->
        MailerConfig.smtp_config(%{"SMTP_HOST" => "smtp.example.com", "SMTP_TLS" => "sometimes"})
      end
    end

    test "parses auth modes case-insensitively" do
      for {value, expected} <- [
            {"never", :never},
            {"always", :always},
            {"if_available", :if_available}
          ] do
        config =
          MailerConfig.smtp_config(%{"SMTP_HOST" => "smtp.example.com", "SMTP_AUTH" => value})

        assert config[:auth] == expected
      end
    end

    test "rejects an invalid auth mode" do
      assert_raise ArgumentError, ~r/SMTP_AUTH must be one of never, always, if_available/, fn ->
        MailerConfig.smtp_config(%{"SMTP_HOST" => "smtp.example.com", "SMTP_AUTH" => "maybe"})
      end
    end

    test "includes the EHLO hostname when set" do
      config =
        MailerConfig.smtp_config(%{
          "SMTP_HOST" => "smtp.example.com",
          "SMTP_HOSTNAME" => "revix.example.com"
        })

      assert config[:hostname] == "revix.example.com"
    end

    test "omits the EHLO hostname when unset or blank" do
      for hostname <- [nil, ""] do
        config =
          MailerConfig.smtp_config(%{
            "SMTP_HOST" => "smtp.example.com",
            "SMTP_HOSTNAME" => hostname
          })

        refute Keyword.has_key?(config, :hostname)
      end
    end

    test "parses a custom retry count" do
      config =
        MailerConfig.smtp_config(%{"SMTP_HOST" => "smtp.example.com", "SMTP_RETRIES" => "3"})

      assert config[:retries] == 3
    end

    test "omits retries when unset or blank" do
      for retries <- [nil, ""] do
        config =
          MailerConfig.smtp_config(%{
            "SMTP_HOST" => "smtp.example.com",
            "SMTP_RETRIES" => retries
          })

        refute Keyword.has_key?(config, :retries)
      end
    end

    test "rejects an invalid retry count" do
      assert_raise ArgumentError, ~r/SMTP_RETRIES must be a positive integer/, fn ->
        MailerConfig.smtp_config(%{"SMTP_HOST" => "smtp.example.com", "SMTP_RETRIES" => "many"})
      end
    end
  end
end
