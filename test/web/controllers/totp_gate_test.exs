defmodule Web.TotpGateTest do
  @moduledoc """
  O portão de acesso: estar logado não basta.

  Duas exigências, testadas aqui:

    * o 2FA precisa estar **ativo** — sem isso o sistema só mostra a tela de
      Segurança;
    * a validação precisa ter menos de **uma hora** — passada a hora, o
      conteúdo fecha até o código ser digitado de novo.
  """
  use Web.ConnCase, async: true

  import Inertia.Testing
  import Core.Fixtures

  alias Core.Accounts.User

  # O painel é permissão (`can_view_dashboard`), e este arquivo usa a home como
  # prova de que "o sistema abriu" — daí ela vir ligada. O que está sob teste é
  # o portão do 2FA, não a régua do painel.
  defp dashboard_user(attrs \\ %{}),
    do: user_fixture(Map.put(Map.new(attrs), :can_view_dashboard, true))

  describe "sem 2FA ativo" do
    setup %{conn: conn} do
      user = dashboard_user(two_factor: false)
      %{conn: log_in(conn, user), user: user}
    end

    test "nenhuma tela do sistema abre", %{user: user} do
      for path <- ["/", "/pedidos", "/pedidos/novo", "/produtos", "/usuarios"] do
        conn = build_conn() |> log_in(user) |> get(path)
        assert redirected_to(conn) == ~p"/seguranca", "#{path} deveria exigir a ativação"
      end
    end

    test "a tela de Segurança abre, para poder ativar", %{conn: conn} do
      conn = get(conn, ~p"/seguranca")

      assert inertia_component(conn) == "Security"
      assert %{twoFactor: %{enabled: false}} = inertia_props(conn)
    end

    test "sair continua possível", %{conn: conn} do
      conn = delete(conn, ~p"/sign-out")

      assert redirected_to(conn) == ~p"/"
    end

    test "ativar libera o sistema", %{conn: conn, user: user} do
      conn = post(conn, ~p"/seguranca/2fa")
      assert %{enrollment: %{secret: secret}} = inertia_props(conn)

      code = secret |> Base.decode32!(padding: false) |> NimbleTOTP.verification_code()
      conn = post(recycle(conn), ~p"/seguranca/2fa/confirmar", %{"code" => code})

      assert %{recoveryCodes: codes} = inertia_props(conn)
      assert length(codes) == 8
      assert Ash.get!(User, user.id, authorize?: false).totp_confirmed_at

      # E o sistema abre, sem pedir o código de novo — acabou de ser digitado.
      conn = get(recycle(conn), ~p"/")
      assert inertia_component(conn) == "Dashboard"
    end
  end

  describe "validação vencida" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_stale(conn, user), user: user}
    end

    test "o conteúdo fecha e o código é pedido de novo", %{conn: conn} do
      conn = get(conn, ~p"/pedidos")

      assert redirected_to(conn) == ~p"/verificacao"
    end

    test "a tela de verificação vem no modo de revalidação", %{conn: conn} do
      conn = get(conn, ~p"/verificacao")

      assert inertia_component(conn) == "Auth/TwoFactor"
      assert %{mode: "reverify"} = inertia_props(conn)
    end

    test "o código certo devolve a pessoa para onde ela ia", %{conn: conn, user: user} do
      # A tentativa barrada guarda o destino...
      conn = conn |> get(~p"/produtos") |> recycle()

      code = NimbleTOTP.verification_code(user.totp_secret)
      conn = post(conn, ~p"/verificacao", %{"code" => code})

      # ...e a revalidação leva de volta para lá, não para a home.
      assert redirected_to(conn) == ~p"/produtos"

      conn = get(recycle(conn), ~p"/produtos")
      assert inertia_component(conn) == "Products/Index"
    end

    test "o código errado mantém o conteúdo fechado", %{conn: conn} do
      conn = conn |> post(~p"/verificacao", %{"code" => "000000"}) |> recycle()

      assert get(conn, ~p"/") |> redirected_to() == ~p"/verificacao"
    end

    test "a sessão continua de pé — é só o código que falta", %{conn: conn, user: user} do
      conn = get(conn, ~p"/verificacao")

      # A tela é servida (200), não um redirect para o login: quem já provou a
      # senha não a digita de novo. E o usuário segue nos props.
      assert conn.status == 200
      assert %{user: %{id: id}} = inertia_props(conn)
      assert id == user.id
    end

    test "desligar o 2FA exige validação recente", %{conn: conn, user: user} do
      conn = post(conn, ~p"/seguranca/2fa/desligar")

      assert redirected_to(conn) == ~p"/verificacao"
      assert Ash.get!(User, user.id, authorize?: false).totp_confirmed_at
    end
  end

  describe "validação em dia" do
    test "o sistema abre normalmente", %{conn: conn} do
      conn = conn |> log_in(dashboard_user()) |> get(~p"/")

      assert inertia_component(conn) == "Dashboard"
    end

    test "a tela de verificação não fica no caminho", %{conn: conn} do
      conn = conn |> log_in(dashboard_user()) |> get(~p"/verificacao")

      assert redirected_to(conn) == ~p"/"
    end
  end
end
