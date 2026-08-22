defmodule Web.Plugs.RequireAdmin do
  @moduledoc """
  Só admin passa. As policies do Ash já barrariam a operação; o plug existe
  para a pessoa receber um aviso em vez de uma tela de erro.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(%{assigns: %{current_user: %{role: :admin}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> put_flash(:error, "Essa área é só do administrador.")
    |> redirect(to: "/")
    |> halt()
  end
end
