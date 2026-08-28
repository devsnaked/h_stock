defmodule Core.Calculations.Arithmetic do
  @moduledoc """
  Conta de `Decimal` entre dois campos do próprio registro, em memória.

  Existe pela mesma razão do [`Core.Calculations.Rollup`](`Core.Calculations.Rollup`),
  mas por um motivo mais grave: **o SQLite não tem tipo decimal**. Um
  `calculate ..., expr(remaining_grams * cost_per_gram)` vira, no SQL que o
  AshSqlite gera, `CAST(? AS REAL) * CAST(? AS REAL)` — ponto flutuante. Mil
  gramas a R$ 0,0071 voltavam do banco como `7.1000000000000005` em vez de
  `7.10`.

  Guardado, o valor está certo: o `ecto_sqlite3` grava `Decimal` como texto e
  lê de volta exato. Quem estraga é a conta feita pelo banco. Então a conta
  sai de lá: os dois operandos são lidos como estão gravados e o `Decimal`
  faz a aritmética no Elixir, onde R$ 0,01 é R$ 0,01.

  O preço disso é o mesmo do `Rollup`: não dá para filtrar nem ordenar por
  estes campos no banco. Nenhum uso atual precisa — a tela recebe os valores
  já serializados, e `Web.Serializers` inclusive já fazia estas mesmas contas
  com `Decimal` do lado do Elixir.

  Uso, com um operando por posição — átomo é atributo, número é constante:

      calculate :remaining_cost, :decimal,
                {Core.Calculations.Arithmetic, mult: [:remaining_grams, :cost_per_gram]}

      calculate :cost_per_kg, :decimal,
                {Core.Calculations.Arithmetic, mult: [:cost_per_gram, 1000]}

      calculate :profit, :decimal,
                {Core.Calculations.Arithmetic, sub: [:total, :cost_total]}

  Operando nulo faz o resultado ser nulo — é o que uma conta em SQL faria.
  """
  use Ash.Resource.Calculation

  @ops [:add, :sub, :mult]

  @impl true
  def init(opts) do
    case Enum.find(@ops, &Keyword.has_key?(opts, &1)) do
      nil ->
        {:error, "Core.Calculations.Arithmetic precisa de uma de #{inspect(@ops)}"}

      op ->
        case Keyword.fetch!(opts, op) do
          [_left, _right] = operands -> {:ok, [op: op, operands: operands]}
          other -> {:error, "#{op} precisa de dois operandos, recebeu #{inspect(other)}"}
        end
    end
  end

  @impl true
  def load(_query, opts, _context) do
    opts |> Keyword.fetch!(:operands) |> Enum.filter(&is_atom/1)
  end

  @impl true
  def calculate(records, opts, _context) do
    [left, right] = Keyword.fetch!(opts, :operands)
    apply_op = op_fun(Keyword.fetch!(opts, :op))

    Enum.map(records, fn record ->
      case {operand(record, left), operand(record, right)} do
        {nil, _right} -> nil
        {_left, nil} -> nil
        {left, right} -> apply_op.(left, right)
      end
    end)
  end

  defp op_fun(:add), do: &Decimal.add/2
  defp op_fun(:sub), do: &Decimal.sub/2
  defp op_fun(:mult), do: &Decimal.mult/2

  defp operand(record, field) when is_atom(field), do: Map.fetch!(record, field)
  defp operand(_record, %Decimal{} = constant), do: constant
  defp operand(_record, constant) when is_integer(constant), do: Decimal.new(constant)
end
