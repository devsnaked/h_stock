defmodule Core.Release do
  @moduledoc """
  Tarefas de banco para o release de produção, onde não há Mix.

  São chamadas pelos scripts em `rel/overlays/bin/`:

      bin/migrate   # sobe as migrações pendentes
      bin/seed      # cria o admin inicial (idempotente)
  """
  @app :h_stock

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Roda `priv/repo/seeds.exs` dentro do release.

  O arquivo é o mesmo do desenvolvimento e é idempotente: rodar de novo não
  duplica nada e não mexe em quem já existe. Dentro do release não há `Mix`,
  então nasce só o admin — a loja de exemplo é exclusiva de `Mix.env() == :dev`.
  """
  def seed do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    @app
    |> Application.app_dir("priv/repo/seeds.exs")
    |> Code.eval_file()

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
