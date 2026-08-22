defmodule Web.Plugs.SetCurrentUser do
  @moduledoc """
  Publica no Inertia os props que toda página precisa.

  O `load_from_session` do AshAuthentication já colocou (ou não) o usuário em
  `conn.assigns.current_user`; aqui a gente só o serializa para o front, junto
  com o CSRF token e as flash messages.

  Precisa rodar DEPOIS do `Inertia.Plug` — `assign_prop/3` opera sobre o
  estado que aquele plug instala na conn.
  """
  import Plug.Conn
  import Inertia.Controller

  alias Web.Serializers

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> assign_prop(:user, Serializers.user(conn.assigns[:current_user]))
    # O token de CSRF é rotacionado a cada login/logout. Mandá-lo como prop
    # em toda resposta deixa o front sempre com o valor atual — a `<meta>`
    # renderizada no boot fica velha depois da primeira navegação SPA.
    |> assign_prop(:csrfToken, Plug.CSRFProtection.get_csrf_token())
    |> share_flash()
  end

  # As flash messages só existem no fim do pipeline (um controller pode
  # colocá-las depois deste plug), por isso a leitura vai no before_send.
  defp share_flash(conn) do
    register_before_send(conn, fn conn ->
      flash = conn.assigns[:flash] || %{}

      if map_size(flash) > 0 do
        assign_prop(conn, :flash, flash)
      else
        conn
      end
    end)
  end
end
