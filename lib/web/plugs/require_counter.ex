defmodule Web.Plugs.RequireCounter do
  @moduledoc """
  Barra o entregador nas telas de balcão.

  O app do entregador é uma lista de entregas: ele não vende, não mexe no
  estoque e não vê o resumo da loja. Em vez de uma tela de erro, ele volta
  para `/entregas` — que é a única casa dele aqui dentro.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(%{assigns: %{current_user: %{role: :driver}}} = conn, _opts) do
    conn
    |> put_flash(:error, "Esta tela é do balcão. Aqui estão as suas entregas.")
    |> redirect(to: "/entregas")
    |> halt()
  end

  def call(conn, _opts), do: conn
end
