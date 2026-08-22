defmodule Core.Orders.Changes.ReturnStock do
  @moduledoc """
  Devolve ao estoque tudo o que o pedido tinha baixado.

  A mercadoria volta **para o lote de onde saiu**, não para um lote novo: ela
  continua sendo a mesma compra, com o mesmo custo. Um cancelamento não pode
  inventar estoque sem custo nem alterar o preço médio da prateleira.

  Roda no cancelamento, dentro da mesma transação: ou o pedido fica cancelado
  e o estoque volta, ou nenhuma das duas coisas acontece.
  """
  use Ash.Resource.Change

  alias Core.Inventory
  alias Core.Inventory.Product

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, order ->
      reason =
        case Ash.Changeset.get_argument(changeset, :reason) do
          nil -> "Cancelamento do pedido #{Core.Orders.code(order)}"
          reason -> "Cancelamento do pedido #{Core.Orders.code(order)}: #{reason}"
        end

      order = Ash.load!(order, :items, authorize?: false)

      Enum.reduce_while(order.items, {:ok, order}, fn item, _acc ->
        product = Ash.get!(Product, item.product_id, authorize?: false)

        product
        |> Inventory.return_stock(
          item.grams,
          item.batch_id,
          %{reason: reason, order_id: order.id},
          actor: context.actor,
          authorize?: false
        )
        |> case do
          {:ok, _product} -> {:cont, {:ok, order}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end)
  end
end
