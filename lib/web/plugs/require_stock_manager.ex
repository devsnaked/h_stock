defmodule Web.Plugs.RequireStockManager do
  @moduledoc """
  Deixa passar quem pode mexer no estoque: o admin, sempre, e o funcionário a
  quem o admin liberou `can_manage_stock`.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(%{assigns: %{current_user: %{role: :admin}}} = conn, _opts), do: conn
  def call(%{assigns: %{current_user: %{can_manage_stock: true}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> put_flash(:error, "Você não tem permissão para gerenciar o estoque.")
    |> redirect(to: "/produtos")
    |> halt()
  end
end
