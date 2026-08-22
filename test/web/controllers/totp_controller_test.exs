defmodule Web.TotpControllerTest do
  @moduledoc """
  A garantia que estes testes existem para dar: entre a senha certa e o código
  certo, **não há sessão**. Quem sabe só a senha não entra.
  """
  use Web.ConnCase, async: true

  import Inertia.Testing
  import Core.Fixtures

  alias Core.Accounts.User

  # `user_fixture/1` já entrega a conta com 2FA ativo — é o estado normal do
  # sistema, onde ele é obrigatório. O painel vem liberado porque é nele que
  # estes testes conferem que o login terminou; quem não o alcança abre os
  # pedidos, e isso é assunto de outro arquivo.
  defp enrolled_user(attrs \\ %{}),
    do: user_fixture(Map.put(Map.new(attrs), :can_view_dashboard, true))

  defp sign_in(conn, user, extra \\ %{}) do
    post(
      conn,
      ~p"/auth/user/password/sign_in",
      %{
        "user" =>
          Map.merge(%{"nickname" => to_string(user.nickname), "password" => password()}, extra)
      }
    )
  end

  defp code_for(user) do
    user = Ash.get!(User, user.id, authorize?: false)
    NimbleTOTP.verification_code(user.totp_secret)
  end

  describe "login com 2FA ligado" do
    setup do
      %{user: enrolled_user()}
    end

    test "a senha certa leva à verificação, sem logar", %{conn: conn, user: user} do
      conn = sign_in(conn, user)

      assert redirected_to(conn) == ~p"/verificacao"

      # A prova de que não há sessão: uma rota protegida ainda barra.
      conn = get(recycle(conn), ~p"/")
      assert redirected_to(conn) == ~p"/sign-in"
    end

    test "a tela de verificação aparece", %{conn: conn, user: user} do
      conn = conn |> sign_in(user) |> recycle() |> get(~p"/verificacao")

      assert inertia_component(conn) == "Auth/TwoFactor"
      assert %{attemptsLeft: 5} = inertia_props(conn)
    end

    test "o código certo completa o login", %{conn: conn, user: user} do
      conn = conn |> sign_in(user) |> recycle()

      conn = post(conn, ~p"/verificacao", %{"code" => code_for(user)})
      assert redirected_to(conn) == ~p"/"

      conn = get(recycle(conn), ~p"/")
      assert inertia_component(conn) == "Dashboard"
    end

    test "o código errado não entra e volta para a verificação", %{conn: conn, user: user} do
      conn = conn |> sign_in(user) |> recycle()

      conn = post(conn, ~p"/verificacao", %{"code" => "000000"})
      assert redirected_to(conn) == ~p"/verificacao"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "incorreto"

      conn = get(recycle(conn), ~p"/")
      assert redirected_to(conn) == ~p"/sign-in"
    end

    test "cinco erros descartam o login pendente", %{conn: conn, user: user} do
      conn = conn |> sign_in(user) |> recycle()

      conn =
        Enum.reduce(1..5, conn, fn _, conn ->
          conn |> post(~p"/verificacao", %{"code" => "000000"}) |> recycle()
        end)

      # O bilhete morreu: a verificação já não existe mais.
      conn = get(conn, ~p"/verificacao")
      assert redirected_to(conn) == ~p"/sign-in"
    end

    test "o mesmo código não vale duas vezes", %{conn: conn, user: user} do
      code = code_for(user)

      conn = conn |> sign_in(user) |> recycle()
      conn = conn |> post(~p"/verificacao", %{"code" => code}) |> recycle()
      assert get(conn, ~p"/") |> inertia_component() == "Dashboard"

      # Novo login, mesmo código: recusado.
      conn = build_conn() |> sign_in(user) |> recycle()
      conn = post(conn, ~p"/verificacao", %{"code" => code})

      assert redirected_to(conn) == ~p"/verificacao"
    end

    test "cancelar volta para o login", %{conn: conn, user: user} do
      conn = conn |> sign_in(user) |> recycle()

      conn = post(conn, ~p"/verificacao", %{}) |> recycle()
      conn = post(conn, ~p"/verificacao/cancelar")

      assert redirected_to(conn) == ~p"/sign-in"
    end
  end

  describe "códigos de recuperação" do
    test "um código de recuperação entra e é gasto", %{conn: conn} do
      user = user_fixture()
      [recovery | _] = user.__metadata__.recovery_codes

      conn = conn |> sign_in(user) |> recycle()
      conn = post(conn, ~p"/verificacao", %{"code" => recovery})

      assert redirected_to(conn) == ~p"/"
      assert Ash.get!(User, user.id, authorize?: false).totp_recovery_hashes |> length() == 7

      # O mesmo código não serve de novo.
      conn = build_conn() |> sign_in(user) |> recycle()
      conn = post(conn, ~p"/verificacao", %{"code" => recovery})
      assert redirected_to(conn) == ~p"/verificacao"
    end
  end

  describe "sem login de longa duração" do
    test "nenhuma etapa entrega cookie além da sessão", %{conn: conn} do
      user = enrolled_user()

      conn = sign_in(conn, user)
      assert cookie_names(conn) == ["_h_stock_key"]

      conn = post(recycle(conn), ~p"/verificacao", %{"code" => code_for(user)})
      assert redirected_to(conn) == ~p"/"
      assert cookie_names(conn) == ["_h_stock_key"]
    end

    test "navegador novo começa do login, mesmo logo depois de entrar", %{conn: conn} do
      user = enrolled_user()

      conn = sign_in(conn, user)
      conn = post(recycle(conn), ~p"/verificacao", %{"code" => code_for(user)})
      assert redirected_to(conn) == ~p"/"

      # Outro navegador (sessão nova, sem cookie nenhum) não herda o login.
      assert redirected_to(get(build_conn(), ~p"/")) == ~p"/sign-in"
    end
  end

  defp cookie_names(conn), do: conn.resp_cookies |> Map.keys() |> Enum.sort()

  test "quem ainda não ativou o 2FA é levado para a ativação", %{conn: conn} do
    user = user_fixture(two_factor: false)

    conn = sign_in(conn, user)
    assert redirected_to(conn) == ~p"/"

    # Logado, mas o conteúdo não abre: só a tela de Segurança.
    conn = get(recycle(conn), ~p"/")
    assert redirected_to(conn) == ~p"/seguranca"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Ative a verificação"

    conn = get(recycle(conn), ~p"/seguranca")
    assert inertia_component(conn) == "Security"
  end

  test "a verificação sem login pendente não é acessível", %{conn: conn} do
    conn = get(conn, ~p"/verificacao")

    assert redirected_to(conn) == ~p"/sign-in"
  end
end
