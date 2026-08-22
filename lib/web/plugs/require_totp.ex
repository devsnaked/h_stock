defmodule Web.Plugs.RequireTotp do
  @moduledoc """
  Nada do sistema abre sem a verificação em duas etapas — enquanto ela estiver
  sendo exigida (`config :h_stock, :totp_required`; ver `TotpSession.required?/0`).

  Duas coisas são exigidas de todo mundo que já passou pelo login:

    * **ter o 2FA ativo** — quem ainda não ativou é levado para a tela de
      Segurança e não sai de lá;
    * **ter validado o código há menos de uma hora** — passada a hora, o
      conteúdo fecha e o código é pedido de novo. Só o código: a senha
      continua valendo, a sessão não é derrubada.

  As telas de ativação e de verificação ficam de fora da exigência, senão o
  redirecionamento não teria para onde ir. `/seguranca/2fa/desligar` **não**
  está entre elas de propósito: desligar o 2FA é justamente o que alguém com
  uma sessão roubada tentaria fazer, então exige validação recente.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Web.TotpSession

  # Caminhos que a própria exigência precisa deixar passar. As telas de
  # verificação não entram porque moram no escopo público — quem chega nelas
  # pode nem ter sessão ainda.
  @enrollment_paths ~w(/seguranca /seguranca/2fa /seguranca/2fa/confirmar)
  @always_allowed ~w(/sign-out)

  def init(opts), do: opts

  def call(%{assigns: %{current_user: nil}} = conn, _opts), do: conn

  # Exigência desligada (`config :h_stock, :totp_required`): a sessão vale por
  # si, sem ativação obrigatória nem revalidação por hora.
  def call(conn, _opts) do
    if TotpSession.required?(), do: enforce(conn), else: conn
  end

  defp enforce(conn) do
    path = conn.request_path
    user = conn.assigns.current_user

    cond do
      path in @always_allowed ->
        conn

      is_nil(user.totp_confirmed_at) ->
        require_enrollment(conn, path)

      TotpSession.verified?(conn) ->
        conn

      true ->
        conn
        |> put_session(:return_to, current_path(conn))
        |> redirect(to: "/verificacao")
        |> halt()
    end
  end

  defp require_enrollment(conn, path) when path in @enrollment_paths, do: conn

  defp require_enrollment(conn, _path) do
    conn
    |> put_flash(
      :error,
      "Ative a verificação em duas etapas para usar o sistema."
    )
    |> redirect(to: "/seguranca")
    |> halt()
  end
end
