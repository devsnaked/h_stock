defmodule Core.Changes.InTransaction do
  @moduledoc """
  Roda a ação inteira — hooks incluídos — dentro de uma transação do banco.

  Existe porque o `AshSqlite` responde `false` para `can?(:transact)`: o Ash
  simplesmente **não abre transação** com este data layer. Sem isto, uma ação
  que escreve em três tabelas (lote, saldo do produto e movimentação) pode
  parar no meio e deixar o estoque contando uma história e o histórico outra.

  O `around_transaction` do Ash é o ponto onde a transação existiria, então é
  ele que a abre aqui. Erro devolvido pelos hooks vira `Repo.rollback/1`;
  exceção sobe e o Ecto desfaz do mesmo jeito.

  Ação chamada de dentro de outra (o cancelamento devolve estoque item a
  item) não abre transação própria: a de fora já cobre tudo, e uma transação
  aninhada em SQLite só serviria para confundir o rollback.

  Como o `default_transaction_mode` do repo é `:immediate`, a transação já
  nasce com o lock de escrita do banco — é o que substitui o `SELECT ... FOR
  UPDATE` que o Postgres oferecia e o SQLite não tem.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context), do: wrap(changeset)

  @doc """
  Envolve o changeset na transação. Para changes que já existem e só precisam
  da garantia, sem virar mais uma linha de `change` no recurso.
  """
  @spec wrap(Ash.Changeset.t()) :: Ash.Changeset.t()
  def wrap(changeset) do
    if Core.Repo.in_transaction?() do
      changeset
    else
      Ash.Changeset.around_transaction(changeset, &run/2)
    end
  end

  # O retorno do callback é opaco de propósito: o Ash devolve tuplas de três
  # ou quatro elementos conforme o caso, e o que este hook promete é entregar
  # a mesma coisa que recebeu.
  defp run(changeset, callback) do
    Core.Repo.transaction(fn ->
      case callback.(changeset) do
        {:error, _reason} = error -> Core.Repo.rollback(error)
        result -> result
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, {:error, _reason} = error} -> error
    end
  end
end
