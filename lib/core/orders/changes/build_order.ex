defmodule Core.Orders.Changes.BuildOrder do
  @moduledoc """
  Monta o pedido a partir dos itens pedidos e dá baixa no estoque.

  O cliente manda apenas `%{product_id, batch_id, grams}` — preço, custo,
  subtotal, desconto e total saem daqui. Nada de confiar em valor calculado no
  navegador.

  Cada item diz de qual **lote** sai a mercadoria, porque é o custo daquele
  lote que entra no lucro da venda. Vender 300g do lote barato e 200g do caro
  são duas linhas no pedido, de propósito: elas custaram coisas diferentes.

  Produtos e lotes são lidos de dentro da transação da criação
  (`Core.Changes.InTransaction`, que a abre porque o AshSqlite não abre): duas
  vendas simultâneas do mesmo lote entram em fila, em vez de as duas verem o
  mesmo saldo e estourarem o estoque. Quem as põe em fila é o SQLite, que tem
  um escritor só — a transação nasce em modo `:immediate` e já segura o lock
  de escrita. Não há travamento por linha porque não há o que dividir.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Core.Inventory
  alias Core.Inventory.Batch
  alias Core.Inventory.Product

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Core.Changes.InTransaction.wrap()
    |> Ash.Changeset.before_action(&build(&1, context))
    |> Ash.Changeset.after_action(&take_from_stock(&1, &2, context))
  end

  defp build(changeset, _context) do
    requested = Ash.Changeset.get_argument(changeset, :items)

    with {:ok, requested} <- normalize(requested),
         {:ok, products} <- load_products(requested),
         {:ok, batches} <- load_batches(requested),
         {:ok, items} <- build_items(requested, products, batches) do
      subtotal = items |> Enum.map(& &1.total) |> sum()
      cost_total = items |> Enum.map(& &1.total_cost) |> sum()

      discount =
        discount_total(
          subtotal,
          Ash.Changeset.get_attribute(changeset, :discount_type),
          Ash.Changeset.get_attribute(changeset, :discount_value)
        )

      changeset
      |> Ash.Changeset.force_change_attribute(:subtotal, subtotal)
      |> Ash.Changeset.force_change_attribute(:discount_total, discount)
      |> Ash.Changeset.force_change_attribute(:total, Decimal.sub(subtotal, discount))
      |> Ash.Changeset.force_change_attribute(:cost_total, cost_total)
      |> Ash.Changeset.manage_relationship(:items, items, type: :create)
    else
      {:error, message} ->
        Ash.Changeset.add_error(changeset, field: :items, message: message)
    end
  end

  # Aceita chaves string (vindas do JSON) ou atom (chamadas internas/testes).
  defp normalize(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      product_id = item[:product_id] || item["product_id"]
      batch_id = item[:batch_id] || item["batch_id"]
      grams = item[:grams] || item["grams"]

      case {product_id, batch_id, to_decimal(grams)} do
        {nil, _, _} ->
          {:halt, {:error, "item sem produto"}}

        {_, nil, _} ->
          {:halt, {:error, "escolha de qual lote sai cada item"}}

        {_, _, :error} ->
          {:halt, {:error, "peso inválido"}}

        {product_id, batch_id, {:ok, grams}} ->
          if Decimal.positive?(grams) do
            entry = %{product_id: product_id, batch_id: batch_id, grams: grams}
            {:cont, {:ok, [entry | acc]}}
          else
            {:halt, {:error, "o peso precisa ser maior que zero"}}
          end
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp load_products(requested) do
    ids = requested |> Enum.map(& &1.product_id) |> Enum.uniq()

    products =
      Product
      |> Ash.Query.filter(id in ^ids)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, &1})

    if map_size(products) == length(ids) do
      {:ok, products}
    else
      {:error, "produto não encontrado"}
    end
  end

  defp load_batches(requested) do
    ids = requested |> Enum.map(& &1.batch_id) |> Enum.uniq()

    batches =
      Batch
      |> Ash.Query.filter(id in ^ids)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, &1})

    if map_size(batches) == length(ids) do
      {:ok, batches}
    else
      {:error, "lote não encontrado"}
    end
  end

  defp build_items(requested, products, batches) do
    # O mesmo lote pedido duas vezes vira uma linha só: o total pedido é o que
    # precisa caber naquele lote. Lotes diferentes do mesmo produto continuam
    # separados — custaram preços diferentes.
    requested
    |> Enum.group_by(&{&1.product_id, &1.batch_id}, & &1.grams)
    |> Enum.reduce_while({:ok, []}, fn {{product_id, batch_id}, weights}, {:ok, acc} ->
      product = Map.fetch!(products, product_id)
      batch = Map.fetch!(batches, batch_id)
      grams = sum(weights)

      cond do
        not product.active ->
          {:halt, {:error, "#{product.name} não está mais à venda"}}

        batch.product_id != product.id ->
          {:halt, {:error, "o lote #{batch.label} não é de #{product.name}"}}

        Decimal.compare(grams, batch.remaining_grams) == :gt ->
          {:halt,
           {:error,
            "estoque insuficiente de #{product.name} no lote #{batch.label}: há #{batch.remaining_grams}g"}}

        true ->
          {:cont, {:ok, [item(product, batch, grams) | acc]}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp item(product, batch, grams) do
    %{
      product_id: product.id,
      product_name: product.name,
      grams: grams,
      price_per_gram: product.price_per_gram,
      total: money(Decimal.mult(grams, product.price_per_gram)),
      batch_id: batch.id,
      batch_label: batch.label,
      cost_per_gram: batch.cost_per_gram,
      total_cost: money(Decimal.mult(grams, batch.cost_per_gram))
    }
  end

  defp discount_total(subtotal, :percent, value) do
    subtotal
    |> Decimal.mult(value)
    |> Decimal.div(100)
    |> money()
    |> Decimal.min(subtotal)
  end

  defp discount_total(subtotal, :amount, value), do: value |> money() |> Decimal.min(subtotal)
  defp discount_total(_subtotal, _type, _value), do: Decimal.new(0)

  defp take_from_stock(_changeset, order, context) do
    order = Ash.load!(order, :items, authorize?: false)

    Enum.reduce_while(order.items, {:ok, order}, fn item, _acc ->
      product = Ash.get!(Product, item.product_id, authorize?: false)

      product
      |> Inventory.remove_stock(
        item.grams,
        item.batch_id,
        %{reason: "Pedido #{Core.Orders.code(order)}", order_id: order.id},
        actor: context.actor,
        authorize?: false
      )
      |> case do
        {:ok, _product} -> {:cont, {:ok, order}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp to_decimal(%Decimal{} = value), do: {:ok, value}
  defp to_decimal(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  defp to_decimal(value) when is_float(value), do: {:ok, Decimal.from_float(value)}

  defp to_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> {:ok, decimal}
      _ -> :error
    end
  end

  defp to_decimal(_value), do: :error

  defp sum(values), do: Enum.reduce(values, Decimal.new(0), &Decimal.add/2)
  defp money(value), do: Decimal.round(value, 2)
end
