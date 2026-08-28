defmodule Web.OrderController do
  @moduledoc """
  Pedidos. A policy do `Core.Orders.Order` já limita o que cada um enxerga
  (admin vê tudo, funcionário vê os seus), então aqui não há filtro por dono —
  um pedido de outra pessoa simplesmente não é encontrado.
  """
  use Web, :controller

  require Ash.Query

  alias Core.Inventory.Product
  alias Core.Orders
  alias Core.Orders.Order
  alias Web.Serializers

  # Vinte cabem numa rolada de polegar sem a lista virar um rolo infinito, e
  # é pouco o bastante para a página responder mesmo com um ano de vendas.
  @per_page 20

  def index(conn, params) do
    user = actor(conn)
    filter = params["entrega"]
    search = presence(params["busca"])
    number = page_number(params["pagina"])

    page =
      Order
      |> delivery_filter(filter)
      |> period_filter(params)
      |> search_filter(search)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.load([:user, :driver, :items_count])
      |> Ash.read!(
        actor: user,
        page: [limit: @per_page, offset: (number - 1) * @per_page, count: true]
      )

    conn
    |> assign_prop(
      :orders,
      Enum.map(page.results, &Serializers.order(&1, costs: manages_stock?(user)))
    )
    |> assign_prop(:filter, filter || "todos")
    |> assign_prop(:search, search || "")
    |> assign_prop(:manages_orders, manages_orders?(user))
    |> assign_prop(:page, %{
      number: number,
      size: @per_page,
      count: page.count,
      pages: max(ceil((page.count || 0) / @per_page), 1)
    })
    |> render_inertia("Orders/Index")
  end

  # Página fora de faixa é URL editada à mão ou link velho: cai na primeira,
  # que é o que a pessoa consegue usar, em vez de uma tela de erro.
  defp page_number(value) do
    case Integer.parse(to_string(value)) do
      {number, _rest} when number > 0 -> number
      _other -> 1
    end
  end

  # Busca da lista: nome do cliente, endereço, observação, código do pedido e
  # quem registrou ou está entregando — é assim que a pergunta chega no balcão
  # ("o pedido da Dona Marta", "o A3F291", "o que o João levou").
  #
  # O código não é coluna: ele é derivado do id (`Core.Orders.code/1`), então
  # a comparação desfaz os hífens do uuid no próprio banco.
  defp search_filter(query, nil), do: query

  defp search_filter(query, term) do
    like = "%#{term}%"
    code = term |> String.replace("-", "") |> String.upcase()

    Ash.Query.filter(
      query,
      ilike(customer_name, ^like) or ilike(delivery_address, ^like) or
        ilike(note, ^like) or ilike(user.name, ^like) or ilike(driver.name, ^like) or
        fragment("upper(replace(cast(? as text), '-', '')) like ?", id, ^"#{code}%")
    )
  end

  # Filtro de entrega. Cancelado nunca entra nas fatias de entrega — o pedido
  # deixou de existir para a operação.
  defp delivery_filter(query, "pendentes") do
    Ash.Query.filter(query, status == :completed and delivery_status == :pending)
  end

  defp delivery_filter(query, "caminho") do
    Ash.Query.filter(query, status == :completed and delivery_status == :out_for_delivery)
  end

  defp delivery_filter(query, "entregues") do
    Ash.Query.filter(query, status == :completed and delivery_status == :delivered)
  end

  defp delivery_filter(query, _filter), do: query

  # A lista sem `?de=`/`?ate=` mostra os pedidos recentes de qualquer data; o
  # intervalo só entra quando a tela pede (os cards do dashboard passam).
  defp period_filter(query, %{"de" => _} = params) do
    {start_at, end_at} = params |> date_range() |> then(fn {f, t} -> Core.Clock.range(f, t) end)
    Ash.Query.filter(query, inserted_at >= ^start_at and inserted_at < ^end_at)
  end

  defp period_filter(query, _params), do: query

  @doc """
  Tela de montar pedido.

  Os produtos vêm com os lotes que ainda têm saldo (`open_batches`): a venda
  precisa dizer de qual lote sai a mercadoria, porque é o custo daquele lote
  que vira o lucro. O custo em si só acompanha quem gerencia estoque.
  """
  def new(conn, _params) do
    user = actor(conn)
    costs = manages_stock?(user)

    products =
      Product
      |> Ash.Query.filter(active == true and stock_grams > 0)
      |> Ash.Query.sort(name: :asc)
      |> Ash.Query.load(:open_batches)
      |> Ash.read!(actor: user)

    conn
    |> assign_prop(:products, Enum.map(products, &with_batches(&1, costs)))
    # A venda já pode sair com entregador definido — a lista vai junto, e é
    # curta (só quem está ativo).
    |> assign_prop(:drivers, drivers(user))
    |> render_inertia("Orders/New")
  end

  defp with_batches(product, costs) do
    product
    |> Serializers.product(costs: costs)
    |> Map.put(:batches, Enum.map(product.open_batches, &Serializers.batch(&1, costs: costs)))
  end

  def show(conn, %{"id" => id}) do
    user = actor(conn)

    case fetch(Order, id, actor: user, load: [:user, :driver, :items]) do
      {:ok, order} ->
        conn
        |> assign_prop(
          :order,
          Serializers.order(order, with_items: true, costs: manages_stock?(user))
        )
        # A lista de entregadores é cara à toa numa tela que quase sempre só
        # exibe o pedido: vai como função, então só é buscada quando a página
        # realmente pede (o diálogo de despacho).
        |> assign_prop(:drivers, fn -> drivers(user) end)
        |> render_inertia("Orders/Show")

      :error ->
        not_found(conn, ~p"/pedidos", "Pedido não encontrado.")
    end
  end

  # Entregador nenhum na lista quando quem olha é o próprio entregador: ele
  # não redistribui pedido.
  defp drivers(%{role: :driver}), do: []

  defp drivers(user) do
    Core.Accounts.User
    |> Ash.Query.for_read(:drivers, %{}, actor: user)
    |> Ash.read!(actor: user)
    |> Enum.map(&Serializers.driver/1)
  end

  @doc """
  Manda o pedido pronto para um entregador.

  O pedido continua na fila (`:pending`) até alguém dizer que saiu: quem
  marca a saída é o entregador, do celular dele, na tela de entregas.
  """
  def assign_driver(conn, %{"id" => id} = params) do
    user = actor(conn)

    with {:ok, order} <- fetch(Order, id, actor: user),
         {:ok, order} <-
           Orders.assign_driver(order, params["driver_id"], actor: user, load: [:driver]) do
      conn
      |> put_flash(:info, "Pedido #{Orders.code(order)} enviado para #{order.driver.name}.")
      |> redirect(to: ~p"/pedidos/#{order.id}")
    else
      :error ->
        not_found(conn, ~p"/pedidos", "Pedido não encontrado.")

      {:error, error} ->
        fail(conn, error, ~p"/pedidos/#{id}")
    end
  end

  @doc """
  Candidatos de endereço para o mapa (`GET /pedidos/endereco?q=...`).

  Responde JSON cru — é a única chamada do app que não é uma página Inertia.
  A lista vem do `Core.Geocoding`; serviço fora do ar devolve lista vazia com
  `available: false`, e a tela segue registrando o pedido sem mapa.
  """
  def geocode(conn, params) do
    case Core.Geocoding.search(params["q"] || "") do
      {:ok, places} -> json(conn, %{available: true, results: places})
      {:error, :unavailable} -> json(conn, %{available: false, results: []})
    end
  end

  def create(conn, params) do
    case build_items(params["items"]) do
      {:ok, items} ->
        delivery? = params["needs_delivery"] != false

        attrs = %{
          items: items,
          customer_name: presence(params["customer_name"]),
          note: presence(params["note"]),
          discount_type: params["discount_type"] || "none",
          discount_value: to_decimal(params["discount_value"]) || Decimal.new(0),
          delivery_status: if(delivery?, do: :pending, else: :not_required),
          # Retirada no balcão não guarda endereço: se a pessoa desligou a
          # entrega depois de digitar, o que vale é o último gesto dela.
          delivery_address: if(delivery?, do: presence(params["delivery_address"])),
          delivery_lat: if(delivery?, do: coordinate(params["delivery_lat"])),
          delivery_lon: if(delivery?, do: coordinate(params["delivery_lon"])),
          # Entregador escolhido na hora da venda. Sem entrega não há para
          # quem mandar, e o domínio recusaria a combinação.
          driver_id: if(delivery?, do: presence(params["driver_id"]))
        }

        case Orders.register_order(attrs, actor: actor(conn)) do
          {:ok, order} ->
            conn
            |> put_flash(:info, "Pedido #{Orders.code(order)} registrado.")
            |> redirect(to: ~p"/pedidos/#{order.id}")

          {:error, error} ->
            fail(conn, error, ~p"/pedidos/novo")
        end

      {:error, error} ->
        fail(conn, error, ~p"/pedidos/novo")
    end
  end

  def cancel(conn, %{"id" => id} = params) do
    user = actor(conn)

    case fetch(Order, id, actor: user) do
      {:ok, order} ->
        case Orders.cancel_order(order, %{reason: presence(params["reason"])}, actor: user) do
          {:ok, order} ->
            conn
            |> put_flash(:info, "Pedido #{Orders.code(order)} cancelado e estoque devolvido.")
            |> redirect(to: ~p"/pedidos/#{order.id}")

          {:error, error} ->
            fail(conn, error, ~p"/pedidos/#{id}")
        end

      :error ->
        not_found(conn, ~p"/pedidos", "Pedido não encontrado.")
    end
  end

  @doc """
  Avança (ou desfaz) o estágio de entrega do pedido.

  As três operações moram na mesma action porque são o mesmo gesto na tela —
  um botão que muda de rótulo conforme o estágio.
  """
  def delivery(conn, %{"id" => id, "estagio" => stage}) do
    user = actor(conn)

    with {:ok, order} <- fetch(Order, id, actor: user),
         {:ok, action} <- delivery_action(stage),
         {:ok, order} <- apply(Orders, action, [order, [actor: user]]) do
      conn
      |> put_flash(:info, delivery_message(order))
      |> redirect(to: ~p"/pedidos/#{order.id}")
    else
      :error ->
        not_found(conn, ~p"/pedidos", "Pedido não encontrado.")

      {:error, :invalid_stage} ->
        not_found(conn, ~p"/pedidos/#{id}", "Estágio de entrega inválido.")

      {:error, error} ->
        fail(conn, error, ~p"/pedidos/#{id}")
    end
  end

  defp delivery_action("saiu"), do: {:ok, :mark_out_for_delivery}
  defp delivery_action("entregue"), do: {:ok, :mark_delivered}
  defp delivery_action("reabrir"), do: {:ok, :reopen_delivery}
  defp delivery_action(_stage), do: {:error, :invalid_stage}

  defp delivery_message(%{delivery_status: :out_for_delivery}), do: "Pedido saiu para entrega."
  defp delivery_message(%{delivery_status: :delivered}), do: "Entrega confirmada."
  defp delivery_message(_order), do: "Pedido voltou para a fila de entrega."

  # O carrinho chega como `[%{"product_id" => id, "batch_id" => id,
  # "quantity" => "1,5", "unit" => "kg"}]`. A conversão para gramas é feita
  # aqui; preço, custo e a checagem do lote são do domínio.
  defp build_items(items) when is_list(items) and items != [] do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case {to_grams(item["quantity"], item["unit"]), presence(item["batch_id"])} do
        {%Decimal{} = grams, batch_id} when is_binary(batch_id) ->
          entry = %{product_id: item["product_id"], batch_id: batch_id, grams: grams}
          {:cont, {:ok, [entry | acc]}}

        {%Decimal{}, nil} ->
          {:halt, {:error, [%{field: :items, message: "escolha o lote de cada item"}]}}

        _ ->
          {:halt, {:error, [%{field: :items, message: "informe um peso válido para cada item"}]}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp build_items(_items),
    do: {:error, [%{field: :items, message: "adicione ao menos um produto"}]}

  # Coordenada que a tela mandou junto do endereço escolhido. Lixo aqui não é
  # erro de formulário: o pedido vale sem mapa, então o que não for número
  # simplesmente não é gravado.
  defp coordinate(value) do
    case to_decimal(presence(value)) do
      %Decimal{} = decimal -> decimal
      _other -> nil
    end
  end

  defp presence(nil), do: nil

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(value), do: value
end
