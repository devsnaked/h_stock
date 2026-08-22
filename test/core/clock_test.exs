defmodule Core.ClockTest do
  @moduledoc """
  O ponto destes testes é uma coisa só: "hoje" é o dia da loja, não o dia em
  UTC. Sem isso, uma venda das 21h em São Paulo apareceria no resumo de
  amanhã — bem no horário em que a loja mais vende.
  """
  use ExUnit.Case, async: true

  alias Core.Clock

  test "o dia local começa 3h depois do dia UTC no horário de Brasília" do
    {start_at, end_at} = Clock.day(~D[2026-08-10])

    assert start_at == ~U[2026-08-10 03:00:00Z]
    assert end_at == ~U[2026-08-11 03:00:00Z]
  end

  test "uma venda das 21h locais cai no dia local, não no seguinte" do
    venda = ~U[2026-08-11 00:30:00Z]
    {start_at, end_at} = Clock.day(~D[2026-08-10])

    assert DateTime.compare(venda, start_at) == :gt
    assert DateTime.compare(venda, end_at) == :lt
  end

  test "o intervalo cobre o último instante do dia final" do
    {_start_at, end_at} = Clock.range(~D[2026-08-01], ~D[2026-08-31])

    ultimo_instante = ~U[2026-09-01 02:59:59Z]
    assert DateTime.compare(ultimo_instante, end_at) == :lt
  end

  test "today/0 devolve uma data" do
    assert %Date{} = Clock.today()
  end
end
