defmodule Web.TotpController do
  @moduledoc """
  A tela do código de 6 dígitos, usada em duas situações:

    * **login pendente** — a senha conferiu e falta o segundo fator. Não há
      sessão nenhuma até o código bater (ver `Web.TotpSession`);
    * **revalidação** — a pessoa já está logada, mas a última validação
      passou de uma hora. A sessão continua de pé; o que fica fechado é o
      conteúdo, até o código ser digitado de novo.

  A diferença aparece só no texto da tela e no que acontece no fim.
  """
  use Web, :controller

  alias Core.Accounts.Totp
  alias Core.Accounts.User
  alias Web.AuthController
  alias Web.TotpSession

  def challenge(conn, _params) do
    case mode(conn) do
      {:pending, pending} ->
        render_challenge(conn, "login", TotpSession.max_attempts() - pending.attempts)

      {:reverify, _user} ->
        render_challenge(conn, "reverify", TotpSession.max_attempts())

      :none ->
        redirect_home(conn)
    end
  end

  def verify(conn, params) do
    code = params["code"]

    case mode(conn) do
      {:pending, pending} ->
        case Ash.get(User, pending.user_id, authorize?: false) do
          {:ok, user} -> check_pending(conn, pending, user, code)
          _ -> expired(conn)
        end

      {:reverify, user} ->
        check_reverification(conn, user, code)

      :none ->
        redirect_home(conn)
    end
  end

  def cancel(conn, _params) do
    conn
    |> TotpSession.clear()
    |> redirect(to: ~p"/sign-in")
  end

  # Em qual das duas situações estamos? Um login pendente tem prioridade: se
  # alguém acabou de digitar a senha, é esse login que está esperando.
  defp mode(conn) do
    user = conn.assigns[:current_user]

    case TotpSession.fetch(conn) do
      {:ok, pending} ->
        {:pending, pending}

      :error ->
        if user && user.totp_confirmed_at && not TotpSession.verified?(conn) do
          {:reverify, user}
        else
          :none
        end
    end
  end

  defp render_challenge(conn, mode, attempts_left) do
    conn
    |> assign_prop(:mode, mode)
    |> assign_prop(:attemptsLeft, attempts_left)
    |> render_inertia("Auth/TwoFactor")
  end

  # Primeiro o código do aplicativo; se não bater, tenta como código de
  # recuperação. A ordem importa: código de recuperação é escasso, e não deve
  # ser gasto por engano quando a pessoa só digitou o dígito errado.
  defp check_pending(conn, pending, user, code) do
    if Totp.valid?(user.totp_secret, code, user.totp_last_used_at) do
      {:ok, _user} = User.register_totp_use(user, authorize?: false)
      AuthController.complete_pending(conn, user, pending.token)
    else
      case Totp.consume_recovery_code(user.totp_recovery_hashes, code) do
        {:ok, remaining} ->
          {:ok, _user} = User.consume_recovery_code(user, remaining, authorize?: false)

          conn
          |> put_flash(:info, recovery_used_message(remaining))
          |> AuthController.complete_pending(user, pending.token)

        :error ->
          wrong_code(conn, pending)
      end
    end
  end

  # Na revalidação a sessão já existe: o que muda é só o carimbo de validade.
  defp check_reverification(conn, user, code) do
    return_to = get_session(conn, :return_to) || ~p"/"

    if Totp.valid?(user.totp_secret, code, user.totp_last_used_at) do
      {:ok, _user} = User.register_totp_use(user, authorize?: false)

      conn
      |> TotpSession.mark_verified()
      |> delete_session(:return_to)
      |> redirect(to: return_to)
    else
      case Totp.consume_recovery_code(user.totp_recovery_hashes, code) do
        {:ok, remaining} ->
          {:ok, _user} = User.consume_recovery_code(user, remaining, authorize?: false)

          conn
          |> TotpSession.mark_verified()
          |> delete_session(:return_to)
          |> put_flash(:info, recovery_used_message(remaining))
          |> redirect(to: return_to)

        :error ->
          conn
          |> put_flash(:error, "Código incorreto.")
          |> redirect(to: ~p"/verificacao")
      end
    end
  end

  defp wrong_code(conn, pending) do
    case TotpSession.register_failure(conn, pending) do
      {:ok, conn} ->
        conn
        |> put_flash(:error, "Código incorreto.")
        |> redirect(to: ~p"/verificacao")

      {:blocked, conn} ->
        conn
        |> put_flash(:error, "Muitas tentativas. Entre com a senha de novo.")
        |> redirect(to: ~p"/sign-in")
    end
  end

  defp recovery_used_message(remaining) do
    "Código de recuperação usado. Restam #{length(remaining)} — gere novos em Segurança."
  end

  defp redirect_home(conn) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/")
    else
      expired(conn)
    end
  end

  defp expired(conn) do
    conn
    |> TotpSession.clear()
    |> put_flash(:error, "A verificação expirou. Entre novamente.")
    |> redirect(to: ~p"/sign-in")
  end
end
