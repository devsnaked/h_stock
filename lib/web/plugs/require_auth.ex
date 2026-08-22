defmodule Web.Plugs.RequireAuth do
  @moduledoc """
  Barra requisições sem usuário autenticado, guardando o destino em
  `:return_to` para que o `AuthController.success/4` devolva o usuário
  exatamente onde ele tentou entrar.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(%{assigns: %{current_user: %{}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> put_session(:return_to, current_path(conn))
    |> put_flash(:error, "Você precisa entrar para acessar esta página.")
    |> redirect(to: "/sign-in")
    |> halt()
  end
end
