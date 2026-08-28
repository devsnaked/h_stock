defmodule Core.Calculations.Rollup do
  @moduledoc """
  Soma ou conta um campo dos registros relacionados, em memória.

  Existe porque o SQLite não tem agregados de relacionamento: o `AshSqlite`
  responde `false` para `{:aggregate, _}`, então `sum :total, :items, :grams`
  nem compila. O que dava para escrever no bloco `aggregates` passa a ser um
  cálculo: o relacionamento é carregado junto (`load/3`) e a conta acontece
  no Elixir.

  A diferença que importa: **isto não filtra nem ordena no banco**. Um
  agregado do Postgres virava SQL e podia entrar num `where`/`order_by`;
  este aqui só existe depois que as linhas chegaram. Todos os usos atuais
  apenas leem o valor (`Ash.Query.load/2`), que é o que ele atende.

  Opções:

    * `:relationship` — obrigatório, o `has_many` a percorrer;
    * `:field` — o campo a somar. Sem ele, conta os registros;
    * `:empty` — o valor quando não há relacionado nenhum. O padrão (`nil`)
      é o mesmo do `sum` do Ash; a contagem usa `0`, como o `count`.
  """
  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    if opts[:relationship] do
      {:ok, opts}
    else
      {:error, "Core.Calculations.Rollup precisa de :relationship"}
    end
  end

  @impl true
  def load(_query, opts, _context) do
    case opts[:field] do
      nil -> [opts[:relationship]]
      field -> [{opts[:relationship], [field]}]
    end
  end

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn record ->
      record
      |> Map.fetch!(opts[:relationship])
      |> rollup(opts)
    end)
  end

  # Relacionamento não carregado (política negou a leitura, por exemplo):
  # devolve o vazio em vez de estourar — é o que um agregado faria.
  defp rollup(related, opts) when not is_list(related), do: empty(opts)

  defp rollup(related, opts) do
    case opts[:field] do
      nil ->
        length(related)

      field ->
        case Enum.map(related, &Map.fetch!(&1, field)) do
          [] -> empty(opts)
          values -> Enum.reduce(values, Decimal.new(0), &Decimal.add(&2, &1 || Decimal.new(0)))
        end
    end
  end

  defp empty(opts) do
    case opts[:field] do
      nil -> 0
      _field -> Keyword.get(opts, :empty)
    end
  end
end
