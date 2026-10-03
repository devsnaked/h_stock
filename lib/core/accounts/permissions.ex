defmodule Core.Accounts.Permissions do
  @moduledoc """
  A régua do painel: quem abre a análise da loja, e quais seções de dados.

  O painel não é uma tela só — é um punhado de perguntas diferentes sobre o
  mesmo negócio, e nem toda pergunta é da conta de todo mundo. Faturamento do
  mês, ranking de quem vendeu mais, dinheiro parado no estoque: um balconista
  pode precisar do movimento por hora sem ter nada a ver com o desempenho dos
  colegas. Por isso a permissão vem em duas camadas:

    * `can_view_dashboard` — abre (ou não) o painel inteiro;
    * `dashboard_sections` — dentro dele, quais seções existem para a pessoa.

  O mapa dos pedidos é uma seção como as outras, e por isso é permissão à
  parte: ele mostra onde os clientes moram, que é o dado mais sensível da
  loja.

  Admin enxerga tudo por definição, como no estoque e nos pedidos; entregador
  não enxerga nada (o painel é do balcão, e o domínio zera as permissões dele
  em `Core.Accounts.Changes.NormalizePermissions`).

  Este módulo é a única lista de seções que existe: o recurso usa para validar
  o que o admin marcou, o controller para publicar só o que pode, e o
  serializer para a tela saber o que oferecer. Seção nova entra aqui e aparece
  nos três.

  Custo e lucro continuam sendo outra régua, a do estoque
  (`Web.ControllerHelpers.manages_stock?/1`): liberar a seção de vendas dá o
  faturamento, não a margem.
  """

  # A ordem é a do painel, de cima para baixo. Ela é a canônica: o que vem do
  # formulário é reordenado por ela, então a lista guardada no banco lê como a
  # tela.
  @dashboard_sections [
    :map,
    :sales,
    :receivables,
    :hours,
    :products,
    :team,
    :delivery,
    :stock,
    :recent
  ]

  @doc "Todas as seções de dados do painel, na ordem em que a tela as mostra."
  def dashboard_sections, do: @dashboard_sections

  @doc "Se a pessoa abre o painel. Admin sempre; o resto, se o admin liberou."
  def views_dashboard?(%{role: :admin}), do: true
  def views_dashboard?(%{can_view_dashboard: true}), do: true
  def views_dashboard?(_user), do: false

  @doc """
  As seções que existem para esta pessoa, na ordem do painel.

  Sem o painel, nenhuma — mesmo que a lista guardada diga outra coisa. É o que
  torna `can_view_dashboard` uma chave de verdade, e não só o primeiro de nove
  interruptores independentes.
  """
  def dashboard_sections(%{role: :admin}), do: @dashboard_sections

  def dashboard_sections(%{can_view_dashboard: true, dashboard_sections: sections})
      when is_list(sections) do
    Enum.filter(@dashboard_sections, &(&1 in sections))
  end

  def dashboard_sections(_user), do: []

  @doc "Se uma seção de dados existe para esta pessoa."
  def sees_dashboard_section?(user, section), do: section in dashboard_sections(user)
end
