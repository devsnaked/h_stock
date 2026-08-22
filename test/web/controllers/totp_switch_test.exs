defmodule Web.TotpSwitchTest do
  @moduledoc """
  A chave que desliga a exigência do segundo fator
  (`config :h_stock, :totp_required`).

  Desligada, ninguém é parado — nem quem já ativou. O que **não** pode
  acontecer é o segredo sumir: religar a chave tem de voltar a pedir o mesmo
  código, sem ninguém reativar nada. É isso que o último teste guarda.

  `async: false` porque a chave é configuração da aplicação inteira: dois
  testes mexendo nela ao mesmo tempo se atrapalhariam.
  """
  use Web.ConnCase, async: false

  import Core.Fixtures
  import Inertia.Testing

  alias Core.Accounts.User

  setup do
    anterior = Application.get_env(:h_stock, :totp_required)
    Application.put_env(:h_stock, :totp_required, false)

    on_exit(fn -> Application.put_env(:h_stock, :totp_required, anterior) end)
  end

  # O painel é permissão (`can_view_dashboard`), e estes testes o usam como
  # prova de que "o sistema abriu" — daí ela vir ligada aqui. Quem não a tem
  # abre os pedidos, e o que está sob teste é a chave do 2FA, não a régua do
  # painel.
  defp dashboard_user(attrs \\ %{}),
    do: user_fixture(Map.put(Map.new(attrs), :can_view_dashboard, true))

  defp sign_in(conn, user) do
    post(conn, ~p"/auth/user/password/sign_in", %{
      "user" => %{"nickname" => to_string(user.nickname), "password" => password()}
    })
  end

  test "quem tem 2FA ativo entra direto, sem passar pelo código", %{conn: conn} do
    user = dashboard_user()
    assert Ash.get!(User, user.id, authorize?: false).totp_confirmed_at

    conn = sign_in(conn, user)
    assert redirected_to(conn) == ~p"/"

    conn = get(recycle(conn), ~p"/")
    assert inertia_component(conn) == "Dashboard"
  end

  test "quem nunca ativou usa o sistema sem ser levado para a ativação", %{conn: conn} do
    user = dashboard_user(two_factor: false)

    conn = sign_in(conn, user)
    assert redirected_to(conn) == ~p"/"

    conn = get(recycle(conn), ~p"/")
    assert inertia_component(conn) == "Dashboard"
  end

  test "a revalidação por hora também não fecha o conteúdo", %{conn: conn} do
    conn = conn |> log_in_stale(dashboard_user()) |> get(~p"/")

    assert inertia_component(conn) == "Dashboard"
  end

  test "a tela de Segurança avisa que a verificação está opcional", %{conn: conn} do
    conn = conn |> log_in(user_fixture(two_factor: false)) |> get(~p"/seguranca")

    assert %{twoFactor: %{required: false, enabled: false}} = inertia_props(conn)
  end

  test "religar a chave volta a exigir o código de quem já tinha ativado", %{conn: conn} do
    user = user_fixture()

    # Entra com a exigência desligada...
    assert redirected_to(sign_in(conn, user)) == ~p"/"

    # ...e o segredo continua lá quando ela volta.
    Application.put_env(:h_stock, :totp_required, true)

    conn = sign_in(build_conn(), user)
    assert redirected_to(conn) == ~p"/verificacao"
  end
end
