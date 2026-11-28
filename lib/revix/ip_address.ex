defmodule Revix.IpAddress do
  @moduledoc """
  Classifies IP address tuples (as returned by `:inet.parse_address/1`).

  `public?/1` is false for addresses that aren't reachable on the public
  internet: private, loopback, link-local, carrier-grade NAT, reserved and
  multicast ranges, and IPv4-mapped IPv6 forms of those.
  """

  import Bitwise

  # IPv4: "this network", private, carrier-grade NAT, loopback, link-local,
  # IETF protocol assignments, benchmarking, and multicast/reserved/broadcast.
  def public?({0, _, _, _}), do: false
  def public?({10, _, _, _}), do: false
  def public?({100, b, _, _}) when b in 64..127, do: false
  def public?({127, _, _, _}), do: false
  def public?({169, 254, _, _}), do: false
  def public?({172, b, _, _}) when b in 16..31, do: false
  def public?({192, 0, 0, _}), do: false
  def public?({192, 168, _, _}), do: false
  def public?({198, b, _, _}) when b in 18..19, do: false
  def public?({a, _, _, _}) when a >= 224, do: false
  def public?({_, _, _, _}), do: true

  # IPv6: unspecified, loopback, IPv4-mapped (checked as IPv4), unique-local,
  # link-local, and multicast.
  def public?({0, 0, 0, 0, 0, 0, 0, a}) when a in 0..1, do: false

  def public?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: public?({hi >>> 8, hi &&& 0xFF, lo >>> 8, lo &&& 0xFF})

  def public?({a, _, _, _, _, _, _, _}) when a in 0xFC00..0xFDFF, do: false
  def public?({a, _, _, _, _, _, _, _}) when a in 0xFE80..0xFEBF, do: false
  def public?({a, _, _, _, _, _, _, _}) when a >= 0xFF00, do: false
  def public?({_, _, _, _, _, _, _, _}), do: true
end
