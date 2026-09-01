defmodule Revix.People.PersonNotifierTest do
  use Revix.DataCase, async: true

  import Swoosh.TestAssertions

  alias Revix.People.Person
  alias Revix.People.PersonNotifier
  alias Revix.Sites

  @url "https://example.com/people/signin/tok123"
  @endpoint "https://revix.test/"
  @now ~U[2026-08-30 13:15:00Z]

  defp person(attrs \\ %{}) do
    struct(%Person{email: "person@example.com", confirmed_at: nil}, attrs)
  end

  defp confirmed_person, do: person(%{confirmed_at: ~U[2026-01-01 00:00:00Z]})

  describe "deliver_login_instructions/3 — bodies" do
    test "confirmation email (unconfirmed person) has both text and HTML bodies" do
      assert {:ok, email} = PersonNotifier.deliver_login_instructions(person(), @url)

      assert email.subject =~ "Confirmation instructions"
      assert email.text_body =~ @url
      assert email.text_body =~ "confirm your account"

      assert is_binary(email.html_body) and email.html_body != ""
      assert email.html_body =~ ~s(<a href="#{@url}">#{@url}</a>)
      assert email.html_body =~ "confirm your account"

      assert_email_sent(email)
    end

    test "sign-in email (confirmed person) has both text and HTML bodies" do
      confirmed = person(%{confirmed_at: ~U[2026-01-01 00:00:00Z]})

      assert {:ok, email} = PersonNotifier.deliver_login_instructions(confirmed, @url)

      assert email.subject =~ "Sign in instructions"
      assert email.text_body =~ @url
      assert email.html_body =~ @url
      assert email.html_body =~ "sign into your account"
    end
  end

  describe "deliver_update_email_instructions/3 — bodies" do
    test "has both text and HTML bodies" do
      assert {:ok, email} = PersonNotifier.deliver_update_email_instructions(person(), @url)

      assert email.subject =~ "Update email instructions"
      assert email.text_body =~ @url
      assert email.html_body =~ @url
      assert email.html_body =~ "change your email"
    end
  end

  describe "subject line" do
    test "without an endpoint: base instruction + timestamp, no site name" do
      assert {:ok, email} =
               PersonNotifier.deliver_login_instructions(confirmed_person(), @url, now: @now)

      assert email.subject == "Sign in instructions — Aug 30, 2026 13:15 UTC"
      # From name falls back to the static sender config when no site title.
      assert {"Revix", _addr} = email.from
    end

    test "with an endpoint: prefixed with the site name (default when no site row)" do
      assert {:ok, email} =
               PersonNotifier.deliver_login_instructions(confirmed_person(), @url,
                 endpoint: @endpoint,
                 now: @now
               )

      assert email.subject == "Revix — Sign in instructions — Aug 30, 2026 13:15 UTC"
    end

    test "with a configured site title: uses that title" do
      {:ok, _site} = Sites.update_site(@endpoint, %{title: "Curt's Place"})

      assert {:ok, email} =
               PersonNotifier.deliver_update_email_instructions(person(), @url,
                 endpoint: @endpoint,
                 now: @now
               )

      assert email.subject == "Curt's Place — Update email instructions — Aug 30, 2026 13:15 UTC"
      # The same site title also brands the From name.
      assert {"Curt's Place", _addr} = email.from
    end

    test "timestamp differs between two sends so mail clients thread them separately" do
      {:ok, a} = PersonNotifier.deliver_login_instructions(person(), @url, now: @now)

      {:ok, b} =
        PersonNotifier.deliver_login_instructions(person(), @url,
          now: DateTime.add(@now, 61, :minute)
        )

      assert a.subject != b.subject
    end
  end

  describe "HTML escaping" do
    test "escapes metacharacters in the URL for the HTML body but not the text body" do
      url = "https://example.com/x?a=1&b=2"

      assert {:ok, email} = PersonNotifier.deliver_login_instructions(person(), url)

      assert email.html_body =~ "a=1&amp;b=2"
      refute email.html_body =~ "a=1&b=2"
      assert email.text_body =~ "a=1&b=2"
    end
  end

  describe "plain-text body contract" do
    test "text body still opens with the divider so extract_person_token/1 keeps working" do
      assert {:ok, email} = PersonNotifier.deliver_login_instructions(person(), @url)
      assert String.starts_with?(email.text_body, "\n==============================\n")
    end
  end
end
