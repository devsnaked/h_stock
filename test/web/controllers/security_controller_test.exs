defmodule Web.SecurityControllerTest do
  @moduledoc """
  A ativação precisa sobreviver a errar o código.

  O caminho que quebrava: a pessoa escaneia o QR, digita um dígito errado, a
  tela volta ao botão "Ativar", ela clica — e ganha um segredo NOVO, enquanto
  o aplicativo do celular guardou o antigo. Dali em diante todo código é
  inválido, sem nenhuma pista do motivo.
  """
  use Web.ConnCase, async: true

  import Inertia.Testing
  import Core.Fixtures

  alias Core.Accounts.User

  defp secret_from(conn) do
    %{enrollment: %{secret: secret}} = inertia_props(conn)
    Base.decode32!(secret, padding: false)
  end

  describe "ativação" do
    setup %{conn: conn} do
      user = user_fixture(two_factor: false)
      %{conn: log_in(conn, user), user: user}
    end

    test "o QR aparece ao começar", %{conn: conn} do
      conn = post(conn, ~p"/seguranca/2fa")

      assert inertia_component(conn) == "Security"
      assert %{enrollment: %{qrCode: qr, secret: secret}} = inertia_props(conn)
      assert String.starts_with?(qr, "data:image/svg+xml;base64,")
      assert byte_size(secret) > 0
    end

    test "errar o código mantém o MESMO segredo e o QR na tela", %{conn: conn} do
      conn = post(conn, ~p"/seguranca/2fa")
      secret = secret_from(conn)

      conn = post(recycle(conn), ~p"/seguranca/2fa/confirmar", %{"code" => "000000"})
      assert redirected_to(conn) == ~p"/seguranca"

      # A tela remonta a ativação pendente, em vez de voltar para o começo.
      conn = get(recycle(conn), ~p"/seguranca")
      assert %{enrollment: %{}} = inertia_props(conn)
      assert secret_from(conn) == secret

      # E o próximo código do MESMO segredo ativa, sem precisar rescanear.
      conn =
        post(recycle(conn), ~p"/seguranca/2fa/confirmar", %{
          "code" => NimbleTOTP.verification_code(secret)
        })

      assert %{twoFactor: %{enabled: true}} = inertia_props(conn)
    end

    test "voltar depois de fechar a página encontra a ativação onde parou", %{conn: conn} do
      conn = post(conn, ~p"/seguranca/2fa")
      secret = secret_from(conn)

      # Sai da tela e volta — nada de recomeçar.
      conn = get(recycle(conn), ~p"/seguranca")

      assert secret_from(conn) == secret
    end

    test "gerar outro QR troca o segredo, quando a pessoa pede", %{conn: conn} do
      conn = post(conn, ~p"/seguranca/2fa")
      primeiro = secret_from(conn)

      conn = post(recycle(conn), ~p"/seguranca/2fa")

      refute secret_from(conn) == primeiro
    end

    test "confirmar liga o 2FA e entrega os códigos de recuperação", %{conn: conn, user: user} do
      conn = post(conn, ~p"/seguranca/2fa")
      secret = secret_from(conn)

      conn =
        post(recycle(conn), ~p"/seguranca/2fa/confirmar", %{
          "code" => NimbleTOTP.verification_code(secret)
        })

      assert %{twoFactor: %{enabled: true}, recoveryCodes: codes} = inertia_props(conn)
      assert length(codes) == 8
      assert Ash.get!(User, user.id, authorize?: false).totp_confirmed_at
    end
  end

  describe "tolerância de relógio" do
    setup %{conn: conn} do
      user = user_fixture(two_factor: false)
      %{conn: log_in(conn, user)}
    end

    test "aceita o código da janela anterior e da seguinte", %{conn: conn} do
      conn = post(conn, ~p"/seguranca/2fa")
      secret = secret_from(conn)
      agora = System.os_time(:second)

      # Celular 30s atrasado.
      atrasado = NimbleTOTP.verification_code(secret, time: agora - 30)
      conn = post(recycle(conn), ~p"/seguranca/2fa/confirmar", %{"code" => atrasado})

      assert %{twoFactor: %{enabled: true}} = inertia_props(conn)
    end

    test "recusa o código de duas janelas atrás", %{conn: conn} do
      conn = post(conn, ~p"/seguranca/2fa")
      secret = secret_from(conn)

      antigo = NimbleTOTP.verification_code(secret, time: System.os_time(:second) - 90)
      conn = post(recycle(conn), ~p"/seguranca/2fa/confirmar", %{"code" => antigo})

      assert redirected_to(conn) == ~p"/seguranca"
    end
  end

  test "desligar apaga o segredo", %{conn: conn} do
    user = user_fixture()
    conn = conn |> log_in(user) |> post(~p"/seguranca/2fa/desligar")

    assert redirected_to(conn) == ~p"/seguranca"
    recarregado = Ash.get!(User, user.id, authorize?: false)
    refute recarregado.totp_confirmed_at
    refute recarregado.totp_secret
  end
end
