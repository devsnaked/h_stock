defmodule Web.ProductController do
  @moduledoc """
  Catálogo e estoque.

  Ler é liberado para qualquer usuário autenticado (o funcionário precisa do
  catálogo para montar pedidos); escrever exige admin ou permissão de estoque
  — garantido pelas policies do Ash e antecipado pelo `RequireStockManager`,
  que evita a tela de erro.

  O estoque é movimentado por **lote**: entrada abre um lote novo (com o custo
  pago), saída e ajuste dizem em qual lote estão mexendo. Custo e histórico só
  vão para a tela de quem gerencia estoque (`manages_stock?/1`).
  """
  use Web, :controller

  require Ash.Query

  alias Core.Inventory
  alias Core.Inventory.Batch
  alias Core.Inventory.Product
  alias Core.Inventory.StockMovement
  alias Web.Serializers

  def index(conn, params) do
    user = actor(conn)
    search = params["q"]

    products =
      Product
      |> search_query(search)
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!(actor: user)

    conn
    |> assign_prop(
      :products,
      Enum.map(products, &Serializers.product(&1, costs: manages_stock?(user)))
    )
    |> assign_prop(:search, search)
    |> render_inertia("Products/Index")
  end

  def new(conn, _params) do
    conn
    |> assign_prop(:product, nil)
    |> render_inertia("Products/Form")
  end

  def edit(conn, %{"id" => id}) do
    case fetch(Product, id, actor: actor(conn)) do
      {:ok, product} ->
        conn
        |> assign_prop(:product, Serializers.product(product))
        |> render_inertia("Products/Form")

      :error ->
        not_found(conn, ~p"/produtos", "Produto não encontrado.")
    end
  end

  # Vinte linhas de histórico por vez: é o quanto se lê de uma rolada, e um
  # produto que gira acumula centenas delas.
  @history_size 20

  def show(conn, %{"id" => id} = params) do
    user = actor(conn)
    load = if manages_stock?(user), do: [:stock_cost_value], else: []

    case fetch(Product, id, actor: user, load: load) do
      {:ok, product} -> render_show(conn, product, user, params)
      :error -> not_found(conn, ~p"/produtos", "Produto não encontrado.")
    end
  end

  defp render_show(conn, product, user, params) do
    costs = manages_stock?(user)
    number = page_number(params["historico"])

    batches =
      Batch
      |> Ash.Query.for_read(:for_product, %{product_id: product.id}, actor: user)
      |> Ash.read!()

    # O histórico é do grupo do estoque (policy do recurso); para o resto da
    # casa a tela mostra só o produto e os lotes disponíveis.
    history =
      if costs do
        StockMovement
        |> Ash.Query.for_read(:for_product, %{product_id: product.id}, actor: user)
        |> Ash.read!(
          page: [
            limit: @history_size,
            offset: (number - 1) * @history_size,
            count: true
          ]
        )
      end

    conn
    |> assign_prop(:product, Serializers.product(product, costs: costs))
    |> assign_prop(:batches, Enum.map(batches, &Serializers.batch(&1, costs: costs)))
    |> assign_prop(:movements, movements(history))
    |> assign_prop(:movements_page, movements_page(history, number))
    # O histórico aponta para o pedido que gerou cada saída — mas só vira link
    # para quem alcança pedido de outra pessoa. Sem isso a tela ofereceria um
    # caminho que termina em "pedido não encontrado".
    |> assign_prop(:can_open_orders, manages_orders?(user))
    |> render_inertia("Products/Show")
  end

  defp movements(nil), do: []
  defp movements(page), do: Enum.map(page.results, &Serializers.movement/1)

  defp movements_page(nil, _number), do: %{number: 1, size: @history_size, count: 0, pages: 1}

  defp movements_page(page, number) do
    %{
      number: number,
      size: @history_size,
      count: page.count,
      pages: max(ceil((page.count || 0) / @history_size), 1)
    }
  end

  # Página fora de faixa é URL editada à mão ou link velho: cai na primeira.
  defp page_number(value) do
    case Integer.parse(to_string(value)) do
      {number, _rest} when number > 0 -> number
      _other -> 1
    end
  end

  def create(conn, params) do
    case build_attrs(params) do
      {:ok, attrs} ->
        case Inventory.create_product(attrs, actor: actor(conn)) do
          {:ok, product} ->
            conn
            |> put_flash(:info, "Produto cadastrado.")
            |> redirect(to: ~p"/produtos/#{product.id}")

          {:error, error} ->
            fail(conn, error, ~p"/produtos/novo")
        end

      {:error, error} ->
        fail(conn, error, ~p"/produtos/novo")
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = actor(conn)

    with {:ok, product} <- fetch(Product, id, actor: user) do
      do_update(conn, product, params, user)
    else
      :error -> not_found(conn, ~p"/produtos", "Produto não encontrado.")
    end
  end

  defp do_update(conn, product, params, user) do
    id = product.id

    case build_attrs(params) do
      {:ok, attrs} ->
        # O lote inicial só existe no cadastro: o estoque de um produto que já
        # existe muda pela tela de estoque, nunca por edição de ficha.
        attrs =
          Map.drop(attrs, [
            :initial_stock_grams,
            :initial_cost_per_gram,
            :initial_batch_label
          ])

        case Inventory.update_product(product, attrs, actor: user) do
          {:ok, product} ->
            conn
            |> put_flash(:info, "Produto atualizado.")
            |> redirect(to: ~p"/produtos/#{product.id}")

          {:error, error} ->
            fail(conn, error, ~p"/produtos/#{id}/editar")
        end

      {:error, error} ->
        fail(conn, error, ~p"/produtos/#{id}/editar")
    end
  end

  @doc """
  Entrada, saída ou ajuste de estoque. O tipo vem do formulário porque as três
  operações compartilham a mesma tela.

  Entrada abre um lote e por isso pede o custo; saída e ajuste mexem num lote
  que já existe e por isso pedem `batch_id`.
  """
  def move_stock(conn, %{"id" => id} = params) do
    user = actor(conn)

    with {:ok, product} <- fetch(Product, id, actor: user) do
      do_move_stock(conn, product, params, user)
    else
      :error -> not_found(conn, ~p"/produtos", "Produto não encontrado.")
    end
  end

  defp do_move_stock(conn, product, params, user) do
    id = product.id

    case movement_attrs(product, params) do
      {:ok, kind, grams, opts} ->
        product
        |> apply_movement(kind, grams, opts, user)
        |> case do
          {:ok, _product} ->
            conn
            |> put_flash(:info, "Estoque atualizado.")
            |> redirect(to: ~p"/produtos/#{id}")

          {:error, error} ->
            fail(conn, error, ~p"/produtos/#{id}")
        end

      {:error, error} ->
        fail(conn, error, ~p"/produtos/#{id}")
    end
  end

  # O peso vem na unidade escolhida na tela e o custo na mesma unidade do
  # preço de venda; os dois viram "por grama" aqui, na borda.
  defp movement_attrs(product, params) do
    unit = params["unit"] || to_string(product.unit)
    grams = to_grams(params["quantity"], unit)
    reason = presence(params["reason"])
    batch_id = presence(params["batch_id"])

    cond do
      invalid_number?(grams) or is_nil(grams) ->
        {:error, [%{field: :quantity, message: "informe uma quantidade válida"}]}

      params["kind"] == "in" ->
        entry_attrs(params, unit, grams, reason)

      params["kind"] in ["out", "adjustment"] and is_nil(batch_id) ->
        {:error, [%{field: :batch_id, message: "escolha o lote"}]}

      params["kind"] in ["out", "adjustment"] ->
        {:ok, params["kind"], grams, %{batch_id: batch_id, reason: reason}}

      true ->
        {:error, [%{field: :kind, message: "tipo de movimentação inválido"}]}
    end
  end

  defp entry_attrs(params, unit, grams, reason) do
    case to_price_per_gram(params["cost"], unit) do
      %Decimal{} = cost ->
        {:ok, "in", grams,
         %{cost_per_gram: cost, label: presence(params["batch_label"]), reason: reason}}

      _ ->
        {:error, [%{field: :cost, message: "informe quanto custou esta compra"}]}
    end
  end

  defp apply_movement(product, "in", grams, opts, user),
    do:
      Inventory.add_stock(product, grams, opts.cost_per_gram, Map.delete(opts, :cost_per_gram),
        actor: user
      )

  defp apply_movement(product, "out", grams, opts, user),
    do:
      Inventory.remove_stock(product, grams, opts.batch_id, Map.delete(opts, :batch_id),
        actor: user
      )

  defp apply_movement(product, "adjustment", grams, opts, user),
    do:
      Inventory.adjust_stock(product, grams, opts.batch_id, Map.delete(opts, :batch_id),
        actor: user
      )

  defp presence(nil), do: nil

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(value), do: value

  defp search_query(query, nil), do: query
  defp search_query(query, ""), do: query

  defp search_query(query, search) do
    term = "%#{search}%"
    Ash.Query.filter(query, ilike(name, ^term))
  end

  # Converte o que veio do formulário (preço na unidade do produto, pesos em
  # g/kg, vírgula decimal) para o que o domínio guarda: preço por grama e
  # pesos em gramas.
  defp build_attrs(params) do
    unit = params["unit"] || "kg"

    values = %{
      price_per_gram: to_price_per_gram(params["price"], unit),
      min_stock_grams: to_grams(params["min_stock"], unit) || Decimal.new(0),
      initial_stock_grams: to_grams(params["initial_stock"], unit) || Decimal.new(0),
      initial_cost_per_gram: to_price_per_gram(params["initial_cost"], unit) || Decimal.new(0)
    }

    case Enum.find(values, fn {_key, value} -> invalid_number?(value) end) do
      {key, _} ->
        {:error, [%{field: key, message: "informe um número válido"}]}

      nil ->
        {:ok,
         values
         |> Map.put(:name, params["name"])
         |> Map.put(:unit, unit)
         |> Map.put(:initial_batch_label, presence(params["initial_batch_label"]))
         |> Map.put(:active, params["active"] != false)}
    end
  end
end
