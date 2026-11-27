defmodule Revix.Federation.SignedRequest do
  @moduledoc """
  Checks an inbound signed request before its signature is verified.

  `HTTPSignatures.validate_conn/1` only proves that whatever headers the
  sender listed were signed by the key. It doesn't require the signature to
  cover the request target, host, date and body digest, check that the
  digest matches the body, or reject old dates. Without those checks a
  captured signature could be replayed indefinitely, or reused with a
  different body. Running these checks first also means a malformed request
  never triggers a remote key fetch.

  `Date` may be up to an hour either side of now. Senders sign each delivery
  attempt as they send it, so a legitimate request is never that old.
  """

  @required_headers ~w[(request-target) host date digest]
  @max_skew_seconds 3600
  @digest_algorithms %{"sha-256" => :sha256, "sha-512" => :sha512}

  def validate(headers, body, now \\ DateTime.utc_now()) when is_map(headers) do
    with :ok <- check_signed_headers(headers["signature"]),
         :ok <- check_date(headers["date"], now) do
      check_digest(headers["digest"], body)
    end
  end

  defp check_signed_headers(nil), do: {:error, :unsigned_headers}

  defp check_signed_headers(signature) do
    signed =
      signature
      |> HTTPSignatures.split_signature()
      |> Map.get("headers", [])
      |> Enum.map(&String.downcase/1)

    covers_required(@required_headers -- signed)
  end

  defp covers_required([]), do: :ok
  defp covers_required(_missing), do: {:error, :unsigned_headers}

  defp check_date(nil, _now), do: {:error, :stale_date}

  defp check_date(date, now) do
    date
    |> Timex.parse("{RFC1123}")
    |> within_window(now)
  end

  defp within_window({:ok, %DateTime{} = sent}, now),
    do: fresh(abs(DateTime.diff(now, sent)) <= @max_skew_seconds)

  defp within_window(_unparseable, _now), do: {:error, :stale_date}

  defp fresh(true), do: :ok
  defp fresh(false), do: {:error, :stale_date}

  defp check_digest(nil, _body), do: {:error, :invalid_digest}

  defp check_digest(header, body) do
    header
    |> String.split(",", trim: true)
    |> Enum.map(&parse_digest/1)
    |> Enum.reject(&is_nil/1)
    |> digests_match(body)
  end

  defp parse_digest(entry) do
    with [name, value] <- entry |> String.trim() |> String.split("=", parts: 2),
         {:ok, algorithm} <- Map.fetch(@digest_algorithms, String.downcase(name)) do
      {algorithm, value}
    else
      _ -> nil
    end
  end

  defp digests_match([], _body), do: {:error, :invalid_digest}

  defp digests_match(digests, body),
    do: all_match(Enum.all?(digests, fn {alg, value} -> encoded(alg, body) == value end))

  defp all_match(true), do: :ok
  defp all_match(false), do: {:error, :invalid_digest}

  defp encoded(algorithm, body), do: :crypto.hash(algorithm, body) |> Base.encode64()
end
