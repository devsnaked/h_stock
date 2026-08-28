defmodule Web.HealthController do
  @moduledoc """
  Sinal de vida para o healthcheck do container e do proxy.

  Fica fora de toda pipeline: sem sessão, sem usuário e sem Inertia. Consulta
  o banco de propósito — um processo de pé com o arquivo SQLite inacessível
  não está servindo nada, e o healthcheck precisa enxergar isso.
  """
  use Web, :controller

  def index(conn, _params) do
    Core.Repo.query!("SELECT 1")

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end
end
