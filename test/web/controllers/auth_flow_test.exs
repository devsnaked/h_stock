defmodule Web.AuthFlowTest do
  @moduledoc """
  Circuito de autenticação: as telas são Inertia, mas quem processa os
  formulários são as rotas do AshAuthentication.
  """
  use Web.ConnCase

  import Core.Fixtures

  describe "login" do
    setup do
      %{user: user_fixture(name: "Maria")}
    end

    test "com credenciais válidas segue para o segundo fator", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/auth/user/password/sign_in", %{
          "user" => %{"nickname" => to_string(user.nickname), "password" => password()}
        })

      # A senha sozinha não abre nada: o 2FA é obrigatório neste sistema.
      # O caminho completo até o Dashboard está em `Web.TotpControllerTest`.
      assert redirected_to(conn) == ~p"/verificacao"
    end

    test "com senha errada volta pro sign-in com flash de erro", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/auth/user/password/sign_in", %{
          "user" => %{"nickname" => to_string(user.nickname), "password" => "senha-errada"}
        })

      assert redirected_to(conn) == ~p"/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "incorretos"
    end

    test "usuário desativado não entra", %{conn: conn, user: user} do
      {:ok, _user} = Core.Accounts.User.set_active(user, false, authorize?: false)

      conn =
        post(conn, ~p"/auth/user/password/sign_in", %{
          "user" => %{"nickname" => to_string(user.nickname), "password" => password()}
        })

      assert redirected_to(conn) == ~p"/sign-in"
    end

    test "acertar a senha não entrega credencial de longa duração", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/auth/user/password/sign_in", %{
          "user" => %{"nickname" => to_string(user.nickname), "password" => password()}
        })

      # Não existe "manter conectado": o único cookie da resposta é a sessão,
      # que morre com o navegador.
      assert Map.keys(conn.resp_cookies) == ["_h_stock_key"]
    end
  end

  test "não existe cadastro público", %{conn: conn} do
    conn =
      post(conn, "/auth/user/password/register", %{
        "user" => %{
          "nickname" => "invasor",
          "password" => "senha12345",
          "password_confirmation" => "senha12345"
        }
      })

    # `registration_enabled? false` no recurso: a rota simplesmente não existe.
    assert conn.status == 404
    assert Ash.count!(Core.Accounts.User, authorize?: false) == 0
  end

  test "rota protegida sem sessão redireciona para o login", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/sign-in"
  end
end
