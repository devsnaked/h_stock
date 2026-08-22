defmodule Web.Plugs.RequireDriver do
  @moduledoc """
  Deixa passar só quem entrega.

  A tela de entregas é a lista pessoal do entregador (`Order.for_driver`);
  para quem está no balcão ela seria sempre vazia, e o que essa pessoa quer é
  a fila da loja, em `/pedidos?entrega=pendentes`.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(%{assigns: %{current_user: %{role: :driver}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> redirect(to: "/pedidos?entrega=pendentes")
    |> halt()
  end
end
