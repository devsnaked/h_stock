defmodule Core.Inventory.Changes.ApplyStockChange do
  @moduledoc """
  Mexe num lote, acerta o saldo do produto e grava a movimentação.

  As três coisas acontecem na mesma transação (os hooks de uma ação de update
  do AshPostgres rodam dentro dela), então não existe saldo alterado sem lote
  alterado, nem lote alterado sem linha no histórico.

  Opção `:kind`:

    * `:in` — abre um lote novo com o custo pago e soma ao saldo;
    * `:out` — tira do lote informado, recusando se ele não tiver o peso;
    * `:return` — devolve ao lote de onde saiu (cancelamento de pedido);
    * `:adjustment` — define o saldo do lote e registra a diferença.

  O produto (e, fora de `:in`, o lote) é lido com `FOR UPDATE` antes da
  conta: duas saídas simultâneas entram em fila em vez de as duas partirem do
  mesmo saldo e uma sobrescrever a outra. A ordem do travamento é sempre
  produto → lote, a mesma do `Core.Orders.Changes.BuildOrder`, para as duas
  não se enroscarem.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Core.Inventory.Batch
  alias Core.Inventory.Product
  alias Core.Inventory.StockMovement

  @impl true
  def change(changeset, opts, context) do
    kind = Keyword.fetch!(opts, :kind)
    Ash.Changeset.before_action(changeset, &apply_kind(&1, kind, context))
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

  # O saldo do produto sai do banco, travado, e não de `changeset.data`: o
  # registro em mãos pode ter sido lido antes de outra venda gravar a dela.
  defp locked_stock(changeset) do
    product_id = changeset.data.id

    Product
    |> Ash.Query.filter(id == ^product_id)
    |> Ash.Query.lock("FOR UPDATE")
    |> Ash.read_one!(authorize?: false)
    |> Map.fetch!(:stock_grams)
  end

  defp lock_batch(changeset) do
    batch_id = Ash.Changeset.get_argument(changeset, :batch_id)
    product_id = changeset.data.id

    Batch
    |> Ash.Query.filter(id == ^batch_id and product_id == ^product_id)
    |> Ash.Query.lock("FOR UPDATE")
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
  end
end
