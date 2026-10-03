defmodule Web.DashboardController do
  @moduledoc """
  Tela inicial: a análise da loja.

  Não há atalho de operação aqui — registrar pedido é na tela de pedidos.
  Esta é a tela de olhar números, e por isso ela nasce **vazia**: o
  carregamento inicial leva só o recorte de datas e a lista de seções que
  existem para quem está olhando.

  **Tudo é buscado por seção, sob demanda.** Cada bloco do painel (mapa,
  vendas, a prazo, horários, produtos, equipe, entrega, estoque, últimos
  pedidos) é um `inertia_optional`: não sai daqui no carregamento inicial, e
  só é calculado quando a tela pede aquele bloco — o que o front faz quando
  ele se aproxima da área visível. Assim uma seção pesada não segura as
  outras, e o que ninguém rolou até o fim nem chega a ser consultado no banco.

  **Seção sem permissão não é escondida na tela: ela não existe.** Os props
  são montados percorrendo as seções liberadas para o ator
  (`Core.Accounts.Permissions`), então não há um `if` por bloco que alguém
  possa esquecer — o que não está na lista não vira prop, e uma recarga
  parcial pedida à mão (`?only=team`) não encontra nada para calcular. Quem
  não abre o painel nem chega aqui: é o `Web.Plugs.RequireDashboard`.

  Os números respeitam as policies: o funcionário vê os *seus* pedidos, o
  admin vê os da loja. Lucro e custo são outra régua ainda, a do estoque — o
  mesmo grupo que enxerga custo em qualquer outra tela.
  """
  use Web, :controller

  alias Core.Analytics
  alias Core.Clock
  alias Web.Serializers

  def index(conn, params) do
    user = actor(conn)
    {from, to} = date_range(params)
    sections = dashboard_sections(user)

    context = %{user: user, from: from, to: to, costs: manages_stock?(user)}

    conn
    |> assign_prop(:range, %{from: Date.to_iso8601(from), to: Date.to_iso8601(to)})
    |> assign_prop(:today, Date.to_iso8601(Clock.today()))
    |> assign_prop(:costs, context.costs)
    # A tela desenha os blocos a partir desta lista — ela não sabe de cor
    # quais seções existem.
    |> assign_prop(:sections, sections)
    |> assign_sections(sections, context)
    |> render_inertia("Dashboard")
  end

  defp assign_sections(conn, sections, context) do
    Enum.reduce(sections, conn, fn section, conn ->
      assign_prop(conn, section, inertia_optional(fn -> data(section, context) end))
    end)
  end

  defp data(:map, %{user: user, from: from, to: to, costs: costs}) do
    user
    |> Analytics.map(from, to)
    |> Enum.map(&Serializers.order(&1, costs: costs))
  end

  defp data(:sales, %{user: user, from: from, to: to, costs: costs}),
    do: Analytics.sales(user, from, to, costs)

  defp data(:receivables, %{user: user, from: from, to: to}),
    do: Analytics.receivables(user, from, to)

  defp data(:hours, %{user: user, from: from, to: to}), do: Analytics.hours(user, from, to)

  defp data(:products, %{user: user, from: from, to: to, costs: costs}),
    do: Analytics.products(user, from, to, costs)

  defp data(:team, %{user: user, from: from, to: to}), do: Analytics.team(user, from, to)

  defp data(:delivery, %{user: user, from: from, to: to}), do: Analytics.delivery(user, from, to)

  defp data(:stock, %{user: user, costs: costs}), do: Analytics.stock(user, costs)

  defp data(:recent, %{user: user, from: from, to: to, costs: costs}) do
    user
    |> Analytics.recent(from, to)
    |> Enum.map(&Serializers.order(&1, costs: costs))
  end
end
