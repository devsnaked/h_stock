defmodule Web.AuthController do
  use Web, :controller
  use AshAuthentication.Phoenix.Controller

  alias Web.TotpSession

  def success(conn, activity, user, token) do
    # Com a exigência desligada, nem quem tem 2FA ativo é parado: o segredo
    # continua guardado, só não é pedido. Religar a chave volta a pedi-lo.
    if user.totp_confirmed_at && TotpSession.required?() do
      challenge_totp(conn, user, token)
    else
      complete(conn, user, activity)
    end
  end

  @doc """
  Senha certa, mas a conta tem verificação em duas etapas.

  A sessão **não** é instalada aqui: o token fica num bilhete de espera e só
  vira login depois do código. Do contrário, quem descobriu a senha já
  entraria — que é exatamente o que o segundo fator existe para impedir.
  """
  def challenge_totp(conn, user, token) do
    conn
    |> TotpSession.start(user, token)
    |> redirect(to: ~p"/verificacao")
  end

  @doc false
  def complete(conn, user, _activity) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_flash(:info, "Login efetuado.")
    |> redirect(to: return_to)
  end

  @doc """
  Instala a sessão de um login que ficou esperando o segundo fator.

  É aqui — e só aqui — que o token vai para a sessão: quem acertou a senha e
  parou no código não recebe credencial nenhuma.
  """
  def complete_pending(conn, user, token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    user = Ash.Resource.put_metadata(user, :token, token)

    conn
    |> delete_session(:return_to)
    |> TotpSession.clear()
    |> TotpSession.mark_verified()
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> put_flash(:info, "Login efetuado.")
    |> redirect(to: return_to)
  end

  @doc """
  Login recusado.

  A mensagem é sempre a mesma, e genérica de propósito: dizer "este nickname
  não existe" entregaria a lista de quem trabalha aqui a quem estiver
  tentando. Conta desativada cai no mesmo texto — o filtro de `active` roda
  antes da checagem de senha.
  """
  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "Nickname ou senha incorretos.")
    |> redirect(to: ~p"/sign-in")
  end

  @doc """
  Sair.

  `clear_session/1` derruba a sessão inteira — não há cookie de longa duração
  sobrando para repor o login na requisição seguinte, porque não existe
  nenhum: toda entrada abre uma sessão nova.
  """
  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> clear_session(:h_stock)
    |> put_flash(:info, "Você saiu da sua conta.")
    |> redirect(to: return_to)
  end
end
