defmodule Web.Plugs.RequireDashboard do
  @moduledoc """
  Deixa passar quem abre o painel: o admin, sempre, e quem o admin liberou
  (`can_view_dashboard`).

  O painel é a home do balcão, mas não é a home de todo mundo: quem não o
  alcança começa o dia nos pedidos, que é a tela do trabalho dela — em vez de
  bater numa tela de erro no primeiro toque do dia. A barra de navegação também
  esconde o item (`viewsDashboard` nos props compartilhados), então o desvio
  aqui é para o link antigo, o atalho salvo e a URL digitada.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Core.Accounts.Permissions

  def init(opts), do: opts

  def call(conn, _opts) do
    if Permissions.views_dashboard?(conn.assigns[:current_user]) do
      conn
    else
      conn
      |> put_flash(:error, "Você não tem permissão para ver o painel da loja.")
      |> redirect(to: "/pedidos")
      |> halt()
    end
  end
end
