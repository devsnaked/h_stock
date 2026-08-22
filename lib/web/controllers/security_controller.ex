defmodule Web.SecurityController do
  @moduledoc """
  Ativação da verificação em duas etapas pela própria pessoa.

  Três passos: gerar o segredo, escanear o QR Code, confirmar com o primeiro
  código. Só no último passo o 2FA passa a valer.

  A ativação em andamento mora no banco (`totp_secret` preenchido e
  `totp_confirmed_at` vazio), não numa tela de passagem. É o que garante que
  errar um dígito não jogue a pessoa de volta ao início: a tela é remontada a
  partir do mesmo segredo, e o QR já escaneado continua servindo.
  """
  use Web, :controller

  alias Core.Accounts.Totp
  alias Core.Accounts.User

  def show(conn, _params) do
    user = actor(conn)

    conn
    |> two_factor_prop(user)
    |> maybe_enrollment_prop(user)
    |> render_inertia("Security")
  end

  # A tela precisa saber se a verificação está sendo exigida: com a chave
  # desligada ela deixa de ser porta de entrada e vira uma proteção opcional —
  # e a pessoa pode sair desta página sem ativar nada.

  @doc """
  Gera um segredo novo e mostra o QR Code.

  Chamar de novo troca o segredo — é o "gerar outro QR" de quem escaneou no
  aplicativo errado. Por isso a tela só oferece isso explicitamente: trocar
  sem querer invalidaria o QR que a pessoa acabou de ler.
  """
  def start(conn, _params) do
    user = actor(conn)

    case User.start_totp_enrollment(user, actor: user) do
      {:ok, user} ->
        conn
        |> two_factor_prop(user)
        |> maybe_enrollment_prop(user)
        |> render_inertia("Security")

      {:error, error} ->
        fail(conn, error, ~p"/seguranca")
    end
  end

  @doc "Confere o primeiro código e liga o 2FA, mostrando os códigos de recuperação."
  def confirm(conn, params) do
    user = actor(conn)

    case User.confirm_totp(user, params["code"] || "", actor: user) do
      {:ok, user} ->
        conn
        |> Web.TotpSession.mark_verified()
        |> put_flash(:info, "Verificação em duas etapas ativada.")
        |> two_factor_prop(user)
        # Única vez que estes códigos existem fora do hash. Se a pessoa fechar
        # a página sem anotar, o caminho é desligar e ligar o 2FA de novo.
        |> assign_prop(:recoveryCodes, user.__metadata__[:recovery_codes])
        |> render_inertia("Security")

      {:error, error} ->
        # De volta para `show/2`, que remonta o QR do mesmo segredo pendente —
        # a pessoa só precisa digitar o próximo código.
        fail(conn, error, ~p"/seguranca")
    end
  end

  def disable(conn, _params) do
    user = actor(conn)

    case User.disable_totp(user, actor: user) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Verificação em duas etapas desligada.")
        |> redirect(to: ~p"/seguranca")

      {:error, error} ->
        fail(conn, error, ~p"/seguranca")
    end
  end

  defp two_factor_prop(conn, user) do
    assign_prop(conn, :twoFactor, %{
      enabled: user.totp_confirmed_at != nil,
      required: Web.TotpSession.required?(),
      confirmed_at: user.totp_confirmed_at,
      recovery_codes_left: length(user.totp_recovery_hashes)
    })
  end

  # Ativação pendente: segredo gerado e ainda não confirmado.
  defp maybe_enrollment_prop(conn, %{totp_secret: secret, totp_confirmed_at: nil} = user)
       when not is_nil(secret) do
    uri = Totp.provisioning_uri(secret, to_string(user.nickname))

    assign_prop(conn, :enrollment, %{
      qr_code: Totp.qr_code_data_uri(uri),
      # A mesma URI do QR, para virar link. Quem está lendo esta página no
      # celular não tem como apontar a câmera para a própria tela; tocar no
      # link abre o autenticador já com a conta preenchida.
      uri: uri,
      # A chave em texto é a terceira saída: outro aparelho, aplicativo que
      # não trata `otpauth://`, ou câmera ruim. Dá para digitá-la à mão.
      secret: Base.encode32(secret, padding: false)
    })
  end

  defp maybe_enrollment_prop(conn, _user), do: conn
end
