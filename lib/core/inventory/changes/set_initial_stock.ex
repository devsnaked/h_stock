defmodule Core.Inventory.Changes.SetInitialStock do
  @moduledoc """
  Saldo inicial informado no cadastro do produto.

  Grava o saldo, abre o primeiro lote (com o custo informado) e a movimentação
  de entrada que explica os dois — o histórico começa já batendo com o
  estoque, sem "saldo que apareceu do nada" nem mercadoria sem custo. As três
  escritas são uma transação só (`Core.Changes.InTransaction`, que a abre
  porque o AshSqlite não abre).
  """
  use Ash.Resource.Change

  alias Core.Inventory.Batch
  alias Core.Inventory.StockMovement

  @impl true
  def change(changeset, _opts, context) do
    grams = Ash.Changeset.get_argument(changeset, :initial_stock_grams) || Decimal.new(0)
    cost = Ash.Changeset.get_argument(changeset, :initial_cost_per_gram) || Decimal.new(0)
    label = Ash.Changeset.get_argument(changeset, :initial_batch_label)

    if Decimal.equal?(grams, 0) do
      changeset
    else
      changeset
      |> Core.Changes.InTransaction.wrap()
      |> Ash.Changeset.force_change_attribute(:stock_grams, grams)
      |> Ash.Changeset.after_action(fn _changeset, product ->
        with {:ok, batch} <- open_batch(product, grams, cost, label, context),
             {:ok, _movement} <- record(product, batch, grams, context) do
          # O saldo inicial é uma entrada de mercadoria como qualquer outra, e
          # tem de aparecer no log de estoque: ela não passa pelo
          # `ApplyStockChange`, que é onde as outras se registram.
          Core.Audit.record(:stock_in, product, context.actor,
            summary:
              "Saldo inicial de #{Core.Audit.grams(grams)} a " <>
                "#{Core.Audit.money(cost)}/g no lote #{batch.label}",
            details: %{
              grams: to_string(grams),
              batch_label: batch.label,
              cost_per_gram: to_string(cost),
              balance_after: to_string(grams),
              reason: "Saldo inicial"
            }
          )

          {:ok, product}
        end
      end)
    end
  end

  defp open_batch(product, grams, cost, label, context) do
    Batch
    |> Ash.Changeset.for_create(
      :create,
      %{
        product_id: product.id,
        label: Batch.label_or_default(label),
        cost_per_gram: cost,
        initial_grams: grams,
        remaining_grams: grams,
        user_id: context.actor && context.actor.id
      },
      authorize?: false
    )
    |> Ash.create()
  end

  defp record(product, batch, grams, context) do
    StockMovement
    |> Ash.Changeset.for_create(
      :create,
      %{
        product_id: product.id,
        batch_id: batch.id,
        kind: :in,
        grams: grams,
        balance_after: grams,
        batch_balance_after: grams,
        cost_per_gram: batch.cost_per_gram,
        total_cost: Decimal.round(Decimal.mult(grams, batch.cost_per_gram), 2),
        reason: "Saldo inicial",
        user_id: context.actor && context.actor.id
      },
      authorize?: false
    )
    |> Ash.create()
  end
end
