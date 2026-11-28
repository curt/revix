defmodule RevixWeb.SignInThrottle do
  @moduledoc """
  Rate limits for the sign-in form, counted per client IP and per email over
  fifteen minutes.

  Password attempts are limited to slow guessing; magic-link requests are
  limited harder because each one sends an email. The email is counted
  whether or not an account exists, so a limited response reveals nothing
  about which addresses are registered.
  """

  alias Revix.RateLimiter
  alias RevixWeb.ClientIp

  @window :timer.minutes(15)
  @limits %{
    password: %{email: 10, ip: 50},
    magic_link: %{email: 3, ip: 10}
  }

  def check(conn, kind, email) when is_binary(email) do
    %{email: email_limit, ip: ip_limit} = Map.fetch!(@limits, kind)

    with :ok <- RateLimiter.hit({:sign_in, kind, :ip, ClientIp.get(conn)}, ip_limit, @window) do
      RateLimiter.hit({:sign_in, kind, :email, normalize(email)}, email_limit, @window)
    end
  end

  defp normalize(email), do: email |> String.trim() |> String.downcase()
end
