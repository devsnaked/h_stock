defmodule Web.AuditController do
  @moduledoc """
  O log de auditoria — só admin.

  Uma tela só, cronológica: tudo o que mexeu em estoque e em pedidos, com
  quem fez. A régua de quem entra é a policy de `Core.Audit.Entry`; o
  `Web.Plugs.RequireAdmin` na rota existe para o funcionário receber um aviso
  em vez de uma tela de erro.

  Os filtros são os que a pergunta do administrador costuma ter: "o que houve
  no estoque essa semana?", "o que fulano andou fazendo?", "quem cancelou
  esse pedido?". Nenhum deles é obrigatório — a tela abre no log inteiro, do
  mais recente para trás.
  """
  use Web, :controller

  require Ash.Query

  alias Core.Audit.Entry
  alias Web.Serializers

  @per_page 30

  # Os grupos que a tela oferece. Cada um junta as ações que respondem à mesma
  # pergunta — quem confere pensa em "estoque" e "pedidos", não em doze nomes
  # de evento.
  @groups %{
    "estoque" => [:stock_in, :stock_out, :stock_return, :stock_adjusted, :stock_cost_corrected],
    "produtos" => [:product_created, :product_updated],
    "pedidos" => [
      :order_registered,
      :order_cancelled,
      :order_driver_assigned,
      :order_out_for_delivery,
      :order_delivered,
      :order_reopened
    ]
  }

  def index(conn, params) do
    user = actor(conn)
    group = params["tipo"]
    author = presence(params["quem"])
    search = presence(params["busca"])
    number = page_number(params["pagina"])

    page =
      Entry
      |> group_filter(group)
      |> author_filter(author)
      |> search_filter(search)
      |> period_filter(params)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.load(:user)
      |> Ash.read!(
        actor: user,
        page: [limit: @per_page, offset: (number - 1) * @per_page, count: true]
      )

    conn
    |> assign_prop(:entries, Enum.map(page.results, &Serializers.audit_entry/1))
    |> assign_prop(:filter, group || "todos")
    |> assign_prop(:author, author || "")
    |> assign_prop(:search, search || "")
    |> assign_prop(:authors, authors(user))
    |> assign_prop(:page, %{
      number: number,
      size: @per_page,
      count: page.count,
      pages: max(ceil((page.count || 0) / @per_page), 1)
    })
    |> render_inertia("Audit/Index")
  end

  # Quem já apareceu no log. Sai da própria tabela, e não da lista de
  # usuários: o filtro só precisa oferecer quem de fato fez alguma coisa, e
  # quem foi desativado continua no log e continua filtrável.
  defp authors(user) do
    Entry
    |> Ash.Query.filter(not is_nil(user_id))
    |> Ash.read!(actor: user)
    |> Enum.map(&%{id: &1.user_id, name: &1.user_name})
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end

  defp group_filter(query, group) when is_map_key(@groups, group) do
    Ash.Query.filter(query, action in ^Map.fetch!(@groups, group))
  end

  defp group_filter(query, _group), do: query

  defp author_filter(query, nil), do: query
  defp author_filter(query, user_id), do: Ash.Query.filter(query, user_id == ^user_id)

  # A busca varre o texto que a pessoa enxerga: a frase e o rótulo do produto
  # ou do pedido. É assim que "7A9173" e "Açafrão" encontram a linha.
  defp search_filter(query, nil), do: query

  defp search_filter(query, term) do
    like = "%#{term}%"
    Ash.Query.filter(query, ilike(summary, ^like) or ilike(subject_label, ^like))
  end

  defp period_filter(query, %{"de" => _} = params) do
    {start_at, end_at} = params |> date_range() |> then(fn {f, t} -> Core.Clock.range(f, t) end)
    Ash.Query.filter(query, inserted_at >= ^start_at and inserted_at < ^end_at)
  end

  defp period_filter(query, _params), do: query

  defp page_number(value) do
    case Integer.parse(to_string(value)) do
      {number, _rest} when number > 0 -> number
      _other -> 1
    end
  end

  defp presence(nil), do: nil

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
