defmodule RevixWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use RevixWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint RevixWeb.Endpoint

      use RevixWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import RevixWeb.ConnCase
    end
  end

  setup tags do
    Revix.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in people.

      setup :register_and_log_in_person

  It stores an updated connection and a registered person in the
  test context.
  """
  def register_and_log_in_person(%{conn: conn} = context) do
    person = Revix.PeopleFixtures.person_fixture()
    scope = Revix.People.Scope.for_person(person)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.into([])

    %{conn: log_in_person(conn, person, opts), person: person, scope: scope}
  end

  @doc """
  Logs the given `person` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_person(conn, person, opts \\ []) do
    token = Revix.People.generate_person_session_token(person)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:person_token, token)
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    Revix.PeopleFixtures.override_token_authenticated_at(token, authenticated_at)
  end

  @doc """
  Waits for the place-search Task.async result to be delivered to the LiveView,
  indicated by the loading spinner disappearing from the rendered output.

  Retries up to 10 times with 20 ms between attempts. Use this instead of
  `Process.sleep` after triggering a "locate" event in LiveView tests.
  """
  def wait_for_place_search(view) do
    Enum.reduce_while(1..10, nil, fn _, _ ->
      html = Phoenix.LiveViewTest.render(view)

      if html =~ "loading-spinner" do
        Process.sleep(20)
        {:cont, html}
      else
        {:halt, html}
      end
    end)
  end
end
