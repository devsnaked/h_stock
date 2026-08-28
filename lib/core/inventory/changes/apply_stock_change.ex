defmodule Core.Inventory.Changes.ApplyStockChange do
  @moduledoc """
  Mexe num lote, acerta o saldo do produto e grava a movimentação.

  As três coisas acontecem na mesma transação (`Core.Changes.InTransaction`,
  que a abre porque o AshSqlite não abre), então não existe saldo alterado sem
  lote alterado, nem lote alterado sem linha no histórico.

  Opção `:kind`:

    * `:in` — abre um lote novo com o custo pago e soma ao saldo;
    * `:out` — tira do lote informado, recusando se ele não tiver o peso;
    * `:return` — devolve ao lote de onde saiu (cancelamento de pedido);
    * `:adjustment` — define o saldo do lote e registra a diferença.

  O saldo do produto (e, fora de `:in`, o do lote) é relido do banco dentro da
  transação, e não de `changeset.data`: o registro em mãos pode ter sido lido
  antes de outra venda gravar a dela. Quem põe as saídas simultâneas em fila é
  o próprio SQLite — a transação nasce em modo `:immediate` e segura o lock de
  escrita do banco inteiro até o fim. Não há travamento por linha (nem
  `FOR UPDATE`) aqui: o banco tem um escritor só.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Core.Inventory.Batch
  alias Core.Inventory.Product
  alias Core.Inventory.StockMovement

  @impl true
  def change(changeset, opts, context) do
    kind = Keyword.fetch!(opts, :kind)

    changeset
    |> Core.Changes.InTransaction.wrap()
    |> Ash.Changeset.before_action(&apply_kind(&1, kind, context))
  end

  # Entrada: lote novo. Não há saldo de lote para conferir — só somar.
  defp apply_kind(changeset, :in, context) do
    grams = Ash.Changeset.get_argument(changeset, :grams)
    cost = Ash.Changeset.get_argument(changeset, :cost_per_gram)
    balance = Decimal.add(locked_stock(changeset), grams)

    changeset
    |> Ash.Changeset.force_change_attribute(:stock_grams, balance)
    |> Ash.Changeset.after_action(fn changeset, product ->
      with {:ok, batch} <- open_batch(changeset, product, grams, cost, context),
           {:ok, _movement} <-
             record(changeset, product, batch, context,
               kind: :in,
               audit: :stock_in,
               delta: grams,
               balance: balance,
               batch_balance: grams
             ) do
        {:ok, product}
      end
    end)
  end

  defp apply_kind(changeset, kind, context) do
    grams = Ash.Changeset.get_argument(changeset, :grams)
    current = locked_stock(changeset)

    case lock_batch(changeset) do
      {:ok, batch} ->
        move_batch(changeset, batch, kind, grams, current, context)

      :error ->
        Ash.Changeset.add_error(changeset, field: :batch_id, message: "lote não encontrado")
    end
  end

  defp move_batch(changeset, batch, kind, grams, current, context) do
    {batch_balance, delta} = new_batch_balance(kind, batch.remaining_grams, grams)
    balance = Decimal.add(current, delta)

    cond do
      Decimal.negative?(batch_balance) ->
        Ash.Changeset.add_error(changeset,
          field: :grams,
          message:
            "estoque insuficiente no lote #{batch.label}: há apenas #{batch.remaining_grams}g"
        )

      Decimal.negative?(balance) ->
        Ash.Changeset.add_error(changeset,
          field: :grams,
          message: "estoque insuficiente: há apenas #{current}g disponíveis"
        )

      true ->
        changeset
        |> Ash.Changeset.force_change_attribute(:stock_grams, balance)
        |> Ash.Changeset.after_action(fn changeset, product ->
          with {:ok, batch} <- settle_batch(batch, batch_balance),
               {:ok, _movement} <-
                 record(changeset, product, batch, context,
                   kind: movement_kind(kind),
                   audit: audit_action(kind),
                   delta: delta,
                   balance: balance,
                   batch_balance: batch_balance
                 ) do
            {:ok, product}
          end
        end)
    end
  end

  defp new_batch_balance(:out, remaining, grams),
    do: {Decimal.sub(remaining, grams), Decimal.negate(grams)}

  defp new_batch_balance(:return, remaining, grams), do: {Decimal.add(remaining, grams), grams}

  defp new_batch_balance(:adjustment, remaining, grams),
    do: {grams, Decimal.sub(grams, remaining)}

  # Devolução é entrada no histórico: o que ela tem de diferente é não abrir
  # lote novo, e isso o `batch_id` da movimentação já conta.
  defp movement_kind(:return), do: :in
  defp movement_kind(kind), do: kind

  # O log de auditoria, ao contrário do histórico, separa devolução de
  # entrada: quem confere quer distinguir mercadoria comprada de mercadoria
  # que voltou de uma venda cancelada.
  defp audit_action(:out), do: :stock_out
  defp audit_action(:return), do: :stock_return
  defp audit_action(:adjustment), do: :stock_adjusted

  # O saldo do produto sai do banco, e não de `changeset.data`: o registro em
  # mãos pode ter sido lido antes de outra venda gravar a dela.
  defp locked_stock(changeset) do
    product_id = changeset.data.id

    Product
    |> Ash.Query.filter(id == ^product_id)
    |> Ash.read_one!(authorize?: false)
    |> Map.fetch!(:stock_grams)
  end

  defp lock_batch(changeset) do
    batch_id = Ash.Changeset.get_argument(changeset, :batch_id)
    product_id = changeset.data.id

    Batch
    |> Ash.Query.filter(id == ^batch_id and product_id == ^product_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Batch{} = batch} -> {:ok, batch}
      _ -> :error
    end
  end

  defp open_batch(changeset, product, grams, cost, context) do
    Batch
    |> Ash.Changeset.for_create(
      :create,
      %{
        product_id: product.id,
        label: Batch.label_or_default(Ash.Changeset.get_argument(changeset, :label)),
        cost_per_gram: cost,
        initial_grams: grams,
        remaining_grams: grams,
        user_id: context.actor && context.actor.id
      },
      authorize?: false
    )
    |> Ash.create()
  end

  # Lote sem saldo sai das listas de escolha, mas continua no histórico: é ele
  # que explica o custo das vendas que já aconteceram.
  defp settle_batch(batch, balance) do
    depleted_at =
      if Decimal.positive?(balance), do: nil, else: DateTime.utc_now()

    batch
    |> Ash.Changeset.for_update(
      :update,
      %{remaining_grams: balance, depleted_at: depleted_at},
      authorize?: false
    )
    |> Ash.update()
  end

  defp record(changeset, product, batch, context, fields) do
    delta = Keyword.fetch!(fields, :delta)

    attrs = %{
      product_id: product.id,
      batch_id: batch.id,
      kind: Keyword.fetch!(fields, :kind),
      grams: delta,
      balance_after: Keyword.fetch!(fields, :balance),
      batch_balance_after: Keyword.fetch!(fields, :batch_balance),
      cost_per_gram: batch.cost_per_gram,
      total_cost: Decimal.round(Decimal.mult(delta, batch.cost_per_gram), 2),
      reason: Ash.Changeset.get_argument(changeset, :reason),
      order_id: Ash.Changeset.get_argument(changeset, :order_id),
      user_id: context.actor && context.actor.id
    }

    StockMovement
    |> Ash.Changeset.for_create(:create, attrs, authorize?: false)
    |> Ash.create()
    |> case do
      {:ok, movement} ->
        audit(product, batch, context, fields, attrs)
        {:ok, movement}

      error ->
        error
    end
  end

  # A linha do log de auditoria. Sai daqui, e não das quatro ações, porque
  # este é o funil por onde toda mudança de saldo passa — ação de estoque
  # nova que não escreva o histórico também não mexe no estoque.
  defp audit(product, batch, context, fields, attrs) do
    action = Keyword.fetch!(fields, :audit)
    delta = Keyword.fetch!(fields, :delta)

    Core.Audit.record(action, product, context.actor,
      summary: summary(action, batch, delta, attrs),
      details: %{
        grams: to_string(delta),
        batch_label: batch.label,
        cost_per_gram: to_string(batch.cost_per_gram),
        total_cost: to_string(attrs.total_cost),
        balance_after: to_string(attrs.balance_after),
        batch_balance_after: to_string(attrs.batch_balance_after),
        reason: attrs.reason,
        order_id: attrs.order_id
      }
    )
  end

  defp summary(action, batch, delta, attrs) do
    peso = Core.Audit.grams(delta)
    saldo = Core.Audit.grams(attrs.balance_after)

    base =
      case action do
        :stock_in ->
          "Entrada de #{peso} a #{Core.Audit.money(batch.cost_per_gram)}/g " <>
            "no lote #{batch.label}"

        :stock_out ->
          "Saída de #{peso} do lote #{batch.label}"

        :stock_return ->
          "Devolução de #{peso} ao lote #{batch.label}"

        :stock_adjusted ->
          "Ajuste do lote #{batch.label}: #{sinal(delta)}#{peso}"
      end

    # O motivo, quando existe, já nomeia o pedido ("Pedido 7A9173",
    # "Cancelamento do pedido 7A9173: ..."): repetir o código ao lado dele
    # deixava a frase dizendo a mesma coisa duas vezes.
    [base, attrs.reason || pedido(attrs.order_id), "saldo do produto: #{saldo}"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" — ")
  end

  defp sinal(delta), do: if(Decimal.negative?(delta), do: "−", else: "+")

  defp pedido(nil), do: nil
  defp pedido(order_id), do: "pedido #{Core.Orders.code(order_id)}"
end
