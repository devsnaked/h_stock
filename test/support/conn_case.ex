defmodule Web.ConnCase do
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
  by setting `use Web.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint Web.Endpoint

      use Web, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Web.ConnCase
    end
  end

  setup tags do
    Core.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Deixa a conn autenticada como `user`, sem passar pelo formulário de login.

  O login acontece de verdade (pela ação `:sign_in_with_password`) porque o
  recurso exige presença do token — `store_in_session/2` precisa do token que
  só o sign-in emite e grava. O atalho é pular a tela, não a autenticação.
  """
  def log_in(conn, user, password \\ Core.Fixtures.password()) do
    strategy = AshAuthentication.Info.strategy!(Core.Accounts.User, :password)

    {:ok, signed_in} =
      AshAuthentication.Strategy.action(strategy, :sign_in, %{
        "nickname" => to_string(user.nickname),
        "password" => password
      })

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(signed_in)
    # O sistema exige 2FA validado na última hora; o atalho pula a tela, não
    # a exigência. Use `log_in_stale/2` para testar a revalidação.
    |> Web.TotpSession.mark_verified()
  end

  @doc """
  GET de recarga parcial do Inertia — o que a tela faz quando um bloco pede o
  próprio dado (`inertia_optional` + `WhenVisible`).

  Sem os cabeçalhos de parcial o servidor devolve a página inteira, e os props
  opcionais **não** vêm: é justamente o que eles prometem.
  """
  def get_partial(conn, path, component, keys) do
    # A versão é o hash dos assets estáticos; sem ela o Inertia responde 409
    # pedindo um recarregamento inteiro. Em vez de repetir a conta aqui, o
    # valor sai de uma visita normal à mesma rota — e é dessa visita que a
    # sessão é reaproveitada.
    visited = Phoenix.ConnTest.dispatch(conn, Web.Endpoint, :get, path)

    visited
    |> Phoenix.ConnTest.recycle()
    |> Plug.Conn.put_req_header("x-inertia", "true")
    |> Plug.Conn.put_req_header("x-inertia-version", visited.private.inertia_version)
    |> Plug.Conn.put_req_header("x-inertia-partial-component", component)
    |> Plug.Conn.put_req_header("x-inertia-partial-data", Enum.join(keys, ","))
    |> Phoenix.ConnTest.dispatch(Web.Endpoint, :get, path)
  end

  @doc "Sessão autenticada cuja validação de 2FA já passou da hora."
  def log_in_stale(conn, user) do
    conn
    |> log_in(user)
    |> Plug.Conn.put_session(
      :totp_verified_at,
      DateTime.add(DateTime.utc_now(), -2, :hour)
    )
  end
end
