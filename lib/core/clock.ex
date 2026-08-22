defmodule Core.Clock do
  @moduledoc """
  "Que dia é hoje?" — na hora da loja, não em UTC.

  O banco guarda tudo em UTC, o que é o certo. Mas "vendas de hoje" é uma
  pergunta sobre o dia da loja: em São Paulo, um pedido das 21h já é do dia
  seguinte em UTC, e o resumo do dia mentiria justamente no fim do expediente.
  Este módulo traduz datas locais para as janelas UTC correspondentes.

  O fuso vem de `config :h_stock, :timezone` (padrão `America/Sao_Paulo`).
  """

  @doc "Fuso configurado para a operação."
  @spec timezone() :: String.t()
  def timezone, do: Application.get_env(:h_stock, :timezone, "America/Sao_Paulo")

  @doc "A data de hoje no fuso da loja."
  @spec today() :: Date.t()
  def today do
    DateTime.utc_now()
    |> DateTime.shift_zone!(timezone())
    |> DateTime.to_date()
  end

  @doc """
  Janela UTC que cobre os dias de `from` a `to`, inclusive.

  O fim é exclusivo (`< fim`), então pedidos do último instante do dia entram
  sem depender de precisão de microssegundos.
  """
  @spec range(Date.t(), Date.t()) :: {DateTime.t(), DateTime.t()}
  def range(%Date{} = from, %Date{} = to) do
    {start_of_day(from), start_of_day(Date.add(to, 1))}
  end

  @doc "Janela UTC de um único dia local."
  @spec day(Date.t()) :: {DateTime.t(), DateTime.t()}
  def day(%Date{} = date), do: range(date, date)

  @doc "Janela UTC do dia de hoje na loja."
  @spec today_range() :: {DateTime.t(), DateTime.t()}
  def today_range, do: day(today())

  # Meia-noite local convertida para UTC. Em dias de mudança de horário a
  # meia-noite pode não existir ou existir duas vezes; nos dois casos a
  # escolha do `DateTime.new/4` resolve para um instante válido.
  defp start_of_day(date) do
    case DateTime.new(date, ~T[00:00:00], timezone()) do
      {:ok, datetime} -> DateTime.shift_zone!(datetime, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _just_before, just_after} -> DateTime.shift_zone!(just_after, "Etc/UTC")
    end
  end
end
