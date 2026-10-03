defmodule Core.Orders.Changes.EditItems do
  @moduledoc """
  Troca os itens de um pedido já registrado: muda o peso de uma linha, tira
  uma linha, inclui uma nova — e o estoque acompanha, lote a lote.

  O argumento `items` é a lista **final** do pedido. Cada entrada é uma das
  duas:

    * `%{id: item_id, grams: g}` — linha que já estava no pedido, com o peso
      que deve ficar. Linha que não vem na lista sai do pedido.
    * `%{product_id: p, batch_id: b, grams: g}` — linha nova.

  **Preço e custo continuam congelados.** Linha que já existia guarda o preço
  e o custo da venda; só o peso muda, e os totais dela acompanham. Linha nova
  copia o preço do produto e o custo do lote de agora, como na venda. Lote que
  já estava no pedido continua sendo **a mesma linha** (com o preço dela): o
  pedido nunca tem duas linhas do mesmo lote, como no registro.

  **O estoque anda junto, no mesmo lote.** Peso que sai do pedido volta ao lote
  de onde saiu (`return_stock`); peso que entra sai do lote escolhido
  (`remove_stock`), com a mesma checagem de saldo da venda. As movimentações
  dizem "Edição do pedido …" e apontam para o pedido. Tudo na transação da
  edição: ou pedido, itens e estoque mudam juntos, ou nada muda.

  Subtotal, custo, desconto (o mesmo que o pedido já tinha, recalculado sobre
  o novo subtotal) e total são refeitos aqui — nunca vêm da tela.

  Conta a prazo já paga não muda de valor: com a baixa registrada, mexer nos
  itens reescreveria quanto foi recebido.

  O que mudou vai no contexto (`:item_plan`) para o log de auditoria
  (`Core.Orders.Changes.LogOrderEvent`) descrever, com as linhas de antes e
  de depois.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Core.Inventory
  alias Core.Inventory.Batch
  alias Core.Inventory.Product
  alias Core.Orders.Changes.BuildOrder
  alias Core.Orders.OrderItem

  @impl true
  def change(changeset, _opts, context) do
    case Ash.Changeset.fetch_argument(changeset, :items) do
      {:ok, requested} when is_list(requested) ->
        changeset
        |> Core.Changes.InTransaction.wrap()
        |> Ash.Changeset.before_action(&plan(&1, requested))
        |> Ash.Changeset.after_action(&apply_plan(&1, &2, context))

      _absent ->
        changeset
    end
  end

  # Lido de dentro da transação: o saldo conferido aqui é o que vai ser
  # alterado depois (o SQLite segura o lock de escrita desde o BEGIN).
  defp plan(changeset, requested) do
    order = changeset.data

    existing =
      OrderItem
      |> Ash.Query.filter(order_id == ^order.id)
      |> Ash.Query.sort(id: :asc)
      |> Ash.read!(authorize?: false)

    with {:ok, entries} <- parse(requested),
         {:ok, targets, additions} <- assign(entries, existing),
         {:ok, plan} <- build_plan(existing, targets, additions) do
      cond do
        plan.removals == [] and plan.resizes == [] and plan.creations == [] ->
          changeset

        order.paid_at != nil ->
          Ash.Changeset.add_error(changeset,
            field: :items,
            message: "o pagamento já foi registrado; os itens não mudam mais"
          )

        true ->
          apply_totals(changeset, order, plan)
      end
    else
      {:error, message} -> Ash.Changeset.add_error(changeset, field: :items, message: message)
    end
  end

  # Aceita chaves string (vindas do controller) ou atom (chamadas internas).
  defp parse(requested) do
    Enum.reduce_while(requested, {:ok, []}, fn item, {:ok, acc} ->
      id = item[:id] || item["id"]
      product_id = item[:product_id] || item["product_id"]
      batch_id = item[:batch_id] || item["batch_id"]

      case to_decimal(item[:grams] || item["grams"]) do
        {:ok, grams} ->
          cond do
            not Decimal.positive?(grams) ->
              {:halt, {:error, "o peso precisa ser maior que zero"}}

            id != nil ->
              {:cont, {:ok, [{:existing, id, grams} | acc]}}

            product_id == nil ->
              {:halt, {:error, "item sem produto"}}

            batch_id == nil ->
              {:halt, {:error, "escolha de qual lote sai cada item"}}

            true ->
              {:cont, {:ok, [{:new, product_id, batch_id, grams} | acc]}}
          end

        :error ->
          {:halt, {:error, "peso inválido"}}
      end
    end)
    |> case do
      {:ok, []} -> {:error, "o pedido precisa de ao menos um item"}
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  # Para cada linha existente, o peso que deve ficar; e as linhas novas, já
  # agrupadas por lote. Lote que já está no pedido soma na linha dele.
  defp assign(entries, existing) do
    by_id = Map.new(existing, &{&1.id, &1})
    by_batch = existing |> Enum.reject(&is_nil(&1.batch_id)) |> Map.new(&{&1.batch_id, &1})

    Enum.reduce_while(entries, {:ok, %{}, %{}}, fn
      {:existing, id, grams}, {:ok, targets, additions} ->
        if Map.has_key?(by_id, id) do
          {:cont, {:ok, add(targets, id, grams), additions}}
        else
          {:halt, {:error, "item não pertence a este pedido"}}
        end

      {:new, product_id, batch_id, grams}, {:ok, targets, additions} ->
        case Map.fetch(by_batch, batch_id) do
          {:ok, %{product_id: ^product_id} = item} ->
            {:cont, {:ok, add(targets, item.id, grams), additions}}

          {:ok, _other_product} ->
            {:halt, {:error, "o lote escolhido não é desse produto"}}

          :error ->
            {:cont, {:ok, targets, add(additions, {product_id, batch_id}, grams)}}
        end
    end)
  end

  defp build_plan(existing, targets, additions) do
    zero = Decimal.new(0)

    {removals, kept} =
      existing
      |> Enum.map(&{&1, Map.get(targets, &1.id, zero)})
      |> Enum.split_with(fn {_item, target} -> Decimal.equal?(target, 0) end)

    resizes = Enum.reject(kept, fn {item, target} -> Decimal.equal?(item.grams, target) end)
    increases = Enum.filter(resizes, fn {item, target} -> Decimal.gt?(target, item.grams) end)

    product_ids =
      Enum.map(additions, fn {{product_id, _}, _} -> product_id end) ++
        Enum.map(increases, fn {item, _} -> item.product_id end)

    batch_ids =
      Enum.map(additions, fn {{_, batch_id}, _} -> batch_id end) ++
        Enum.map(increases, fn {item, _} -> item.batch_id end)

    products = load(Product, product_ids)
    batches = load(Batch, batch_ids)

    with :ok <- check_unbatched(resizes, removals),
         :ok <- check_increases(increases, products),
         {:ok, creations} <- creations(additions, products, batches),
         :ok <- check_stock(resizes, creations, batches) do
      if kept == [] and creations == [] do
        {:error, "o pedido precisa de ao menos um item"}
      else
        {:ok,
         %{
           before: existing,
           removals: Enum.map(removals, fn {item, _} -> item end),
           resizes: resizes,
           kept: kept,
           creations: creations
         }}
      end
    end
  end

  defp load(_resource, []), do: %{}

  defp load(resource, ids) do
    ids = Enum.uniq(ids)

    resource
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.id, &1})
  end

  # Linha sem lote não tem para onde devolver nem de onde tirar.
  defp check_unbatched(resizes, removals) do
    touched =
      Enum.map(resizes, fn {item, _} -> item end) ++ Enum.map(removals, fn {item, _} -> item end)

    case Enum.find(touched, &is_nil(&1.batch_id)) do
      nil -> :ok
      item -> {:error, "#{item.product_name} não tem lote registrado e não pode mudar"}
    end
  end

  # Diminuir ou tirar produto desativado pode; vender mais dele, não.
  defp check_increases(increases, products) do
    case Enum.find(increases, fn {item, _} -> not products[item.product_id].active end) do
      nil -> :ok
      {item, _} -> {:error, "#{item.product_name} não está mais à venda"}
    end
  end

  defp creations(additions, products, batches) do
    Enum.reduce_while(additions, {:ok, []}, fn {{product_id, batch_id}, grams}, {:ok, acc} ->
      product = Map.get(products, product_id)
      batch = Map.get(batches, batch_id)

      cond do
        product == nil ->
          {:halt, {:error, "produto não encontrado"}}

        batch == nil ->
          {:halt, {:error, "lote não encontrado"}}

        not product.active ->
          {:halt, {:error, "#{product.name} não está mais à venda"}}

        batch.product_id != product.id ->
          {:halt, {:error, "o lote #{batch.label} não é de #{product.name}"}}

        true ->
          {:cont, {:ok, [BuildOrder.line(product, batch, grams) | acc]}}
      end
    end)
    |> case do
      {:ok, lines} -> {:ok, Enum.reverse(lines)}
      error -> error
    end
  end

  # O que cada lote precisa ceder a mais. Linha nova num lote é sempre lote
  # que não estava no pedido, então não há devolução do mesmo lote para
  # descontar.
  defp check_stock(resizes, creations, batches) do
    increases =
      for {item, target} <- resizes,
          Decimal.gt?(target, item.grams),
          do: {item.batch_id, Decimal.sub(target, item.grams)}

    news = Enum.map(creations, &{&1.batch_id, &1.grams})

    (increases ++ news)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.find_value(:ok, fn {batch_id, amounts} ->
      batch = Map.fetch!(batches, batch_id)
      needed = Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)

      if Decimal.gt?(needed, batch.remaining_grams) do
        {:error,
         "estoque insuficiente no lote #{batch.label}: há #{Core.Audit.grams(batch.remaining_grams)} além do que já está no pedido"}
      end
    end)
  end

  defp apply_totals(changeset, order, plan) do
    kept =
      Enum.map(plan.kept, fn {item, target} ->
        if Decimal.equal?(item.grams, target) do
          %{total: item.total, total_cost: item.total_cost}
        else
          resized(item, target)
        end
      end)

    lines = kept ++ plan.creations
    subtotal = lines |> Enum.map(& &1.total) |> sum()
    cost_total = lines |> Enum.map(& &1.total_cost) |> sum()
    discount = BuildOrder.discount_total(subtotal, order.discount_type, order.discount_value)

    changeset
    |> Ash.Changeset.force_change_attribute(:subtotal, subtotal)
    |> Ash.Changeset.force_change_attribute(:discount_total, discount)
    |> Ash.Changeset.force_change_attribute(:total, Decimal.sub(subtotal, discount))
    |> Ash.Changeset.force_change_attribute(:cost_total, cost_total)
    |> Ash.Changeset.set_context(%{item_plan: describe(plan)})
  end

  # Peso novo, preço e custo de sempre.
  defp resized(item, grams) do
    %{
      grams: grams,
      total: money(Decimal.mult(grams, item.price_per_gram)),
      total_cost: money(Decimal.mult(grams, item.cost_per_gram))
    }
  end

  defp describe(plan) do
    sentences =
      Enum.map(plan.resizes, fn {item, target} ->
        "#{line_label(item)}: #{Core.Audit.grams(item.grams)} → #{Core.Audit.grams(target)}"
      end) ++
        Enum.map(
          plan.creations,
          &"Item incluído: #{line_label(&1)}, #{Core.Audit.grams(&1.grams)}"
        ) ++
        Enum.map(
          plan.removals,
          &"Item removido: #{line_label(&1)}, #{Core.Audit.grams(&1.grams)}"
        )

    after_lines =
      Enum.map(plan.kept, fn {item, target} -> snapshot(%{item | grams: target}) end) ++
        Enum.map(plan.creations, &snapshot/1)

    Map.merge(plan, %{
      sentences: sentences,
      items_before: Enum.map(plan.before, &snapshot/1),
      items_after: after_lines
    })
  end

  defp line_label(%{product_name: name, batch_label: nil}), do: name
  defp line_label(%{product_name: name, batch_label: label}), do: "#{name} (#{label})"

  defp snapshot(line) do
    %{
      product_name: line.product_name,
      batch_label: line.batch_label,
      grams: to_string(line.grams),
      price_per_gram: to_string(line.price_per_gram)
    }
  end

  defp apply_plan(changeset, order, context) do
    case changeset.context[:item_plan] do
      nil -> {:ok, order}
      plan -> run(plan, order, context)
    end
  end

  # Devoluções primeiro, saídas depois: o lote nunca passa por um saldo que
  # não existe no meio do caminho.
  defp run(plan, order, context) do
    reason = "Edição do pedido #{Core.Orders.code(order)}"
    meta = %{reason: reason, order_id: order.id}

    steps =
      Enum.map(plan.removals, &{:remove_line, &1}) ++
        for(
          {item, target} <- plan.resizes,
          Decimal.lt?(target, item.grams),
          do: {:shrink, item, target}
        ) ++
        for(
          {item, target} <- plan.resizes,
          Decimal.gt?(target, item.grams),
          do: {:grow, item, target}
        ) ++
        Enum.map(plan.creations, &{:new_line, &1})

    Enum.reduce_while(steps, {:ok, order}, fn step, ok ->
      case step(step, order, meta, context) do
        :ok -> {:cont, ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp step({:remove_line, item}, _order, meta, context) do
    with :ok <- move(:return_stock, item.product_id, item.grams, item.batch_id, meta, context) do
      item |> Ash.destroy(authorize?: false) |> ok()
    end
  end

  defp step({:shrink, item, target}, _order, meta, context) do
    with :ok <-
           move(
             :return_stock,
             item.product_id,
             Decimal.sub(item.grams, target),
             item.batch_id,
             meta,
             context
           ) do
      resize(item, target)
    end
  end

  defp step({:grow, item, target}, _order, meta, context) do
    with :ok <-
           move(
             :remove_stock,
             item.product_id,
             Decimal.sub(target, item.grams),
             item.batch_id,
             meta,
             context
           ) do
      resize(item, target)
    end
  end

  defp step({:new_line, line}, order, meta, context) do
    with :ok <- move(:remove_stock, line.product_id, line.grams, line.batch_id, meta, context) do
      OrderItem
      |> Ash.Changeset.for_create(:create, Map.put(line, :order_id, order.id), authorize?: false)
      |> Ash.create()
      |> ok()
    end
  end

  defp move(kind, product_id, grams, batch_id, meta, context) do
    product = Ash.get!(Product, product_id, authorize?: false)

    Inventory
    |> apply(kind, [product, grams, batch_id, meta, [actor: context.actor, authorize?: false]])
    |> ok()
  end

  defp resize(item, target) do
    item
    |> Ash.Changeset.for_update(:resize, resized(item, target), authorize?: false)
    |> Ash.update()
    |> ok()
  end

  defp ok({:ok, _record}), do: :ok
  defp ok(:ok), do: :ok
  defp ok({:error, error}), do: {:error, error}

  defp add(map, key, grams), do: Map.update(map, key, grams, &Decimal.add(&1, grams))

  defp to_decimal(%Decimal{} = value), do: {:ok, value}
  defp to_decimal(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  defp to_decimal(value) when is_float(value), do: {:ok, Decimal.from_float(value)}

  defp to_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> {:ok, decimal}
      _other -> :error
    end
  end

  defp to_decimal(_value), do: :error

  defp sum(values), do: Enum.reduce(values, Decimal.new(0), &Decimal.add/2)
  defp money(value), do: Decimal.round(value, 2)
end
