defmodule Revix.URLsTest do
  use ExUnit.Case, async: true

  alias RevixWeb.CanonicalRoutes

  # CLAUDE.md: modules under lib/revix/ must not call RevixWeb.*. The
  # application module is the exception: it starts the web endpoint.
  test "the domain layer never refers to the web layer" do
    offenders =
      for path <- Path.wildcard("lib/revix/**/*.ex"),
          path != "lib/revix/application.ex",
          File.read!(path) =~ "RevixWeb",
          do: path

    assert offenders == []
  end

  test "builds the same URLs as the web layer's canonical routes" do
    person = %Revix.People.Person{id: "abcdefghijk", avatar: nil, uri: "u", username: nil}

    for {fun, args} <- [
          person_inbox_url: ["abcdefghijk"],
          person_outbox_url: ["abcdefghijk"],
          person_followers_url: ["abcdefghijk"],
          person_following_url: ["abcdefghijk"],
          person_liked_url: ["abcdefghijk"],
          entry_likes_url: ["abcdefghijk"],
          entry_replies_url: ["abcdefghijk"],
          avatar_url: [person],
          home_url: [],
          notification_settings_url: []
        ] do
      assert apply(Revix.URLs, fun, args) == apply(CanonicalRoutes, fun, args), "#{fun}"
    end
  end

  test "absolute_url/1 puts a path on this site's origin" do
    assert Revix.URLs.absolute_url("/uploads/x.jpg") ==
             String.trim_trailing(CanonicalRoutes.home_url(), "/") <> "/uploads/x.jpg"
  end

  test "local_host/0 is this site's configured host" do
    assert Revix.URLs.local_host() == URI.parse(CanonicalRoutes.home_url()).host
  end
end
