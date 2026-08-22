defmodule Web.AuthPageController do
  @moduledoc """
  Só as *telas* de autenticação (React/Inertia).

  Quem processa os formulários é o `Web.AuthController`, montado pelas rotas
  de `auth_routes` do AshAuthentication — este controller nunca toca no
  usuário, apenas renderiza a página e passa os caminhos de POST como props.
  """
  use Web, :controller

  def sign_in(conn, _params) do
    render_inertia(conn, "Auth/SignIn")
  end
end
