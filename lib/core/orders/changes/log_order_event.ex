defmodule Core.Orders.Changes.LogOrderEvent do
  @moduledoc """
  Registra no log de auditoria o que aconteceu com um pedido.

  O pedido já guardava **quando** cada passo aconteteu — `cancelled_at`,
  `assigned_at`, `out_for_delivery_at`, `delivered_at` — mas não **quem** deu
  o passo. Só a venda tinha dono (`user_id`). Era o buraco mais incômodo do
  sistema para quem confere: "esse pedido foi cancelado ontem" sem "por
  quem", e o cancelamento é justamente a ação que devolve mercadoria ao
  estoque.

  Cada ação do ciclo de vida passa a escrever a sua linha. A change vai por
  último na lista do recurso de propósito: os hooks rodam na ordem em que
  foram registrados, e o log precisa descrever o pedido **depois** de a ação
  ter mexido nele.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    action = Keyword.fetch!(opts, :action)

    Ash.Changeset.after_action(changeset, fn changeset, order ->
      Core.Audit.record(action, order, context.actor,
        summary: summary(action, changeset, order),
        details: details(action, changeset, order)
      )

      {:ok, order}
    end)
  end

  defp summary(:order_registered, changeset, order) do
    itens = changeset |> Ash.Changeset.get_argument(:items) |> length()

    [
      "Venda de #{Core.Audit.money(order.total)} em #{itens} #{plural(itens)}",
      cliente(order),
      entrega(order)
    ]
    |> juntar()
  end

  defp summary(:order_cancelled, changeset, order) do
    [
      "Pedido cancelado e estoque devolvido",
      "valor #{Core.Audit.money(order.total)}",
      Ash.Changeset.get_argument(changeset, :reason)
    ]
    |> juntar()
  end

  defp summary(:order_driver_assigned, _changeset, order),
    do: juntar(["Entrega despachada para #{entregador(order)}", cliente(order)])

  defp summary(:order_out_for_delivery, _changeset, order),
    do: juntar(["Saiu para entrega com #{entregador(order)}", cliente(order)])

  defp summary(:order_delivered, _changeset, order),
    do: juntar(["Entrega concluída por #{entregador(order)}", cliente(order)])

  defp summary(:order_reopened, _changeset, _order),
    do: "Entrega reaberta: o pedido voltou para a fila, sem entregador"

  defp details(:order_registered, changeset, order) do
    %{
      total: to_string(order.total),
      subtotal: to_string(order.subtotal),
      discount_total: to_string(order.discount_total),
      cost_total: to_string(order.cost_total),
      items: changeset |> Ash.Changeset.get_argument(:items) |> length(),
      customer_name: order.customer_name,
      delivery_status: to_string(order.delivery_status)
    }
  end

  defp details(:order_cancelled, changeset, order) do
    %{
      total: to_string(order.total),
      reason: Ash.Changeset.get_argument(changeset, :reason),
      cancelled_at: to_string(order.cancelled_at)
    }
  end

  defp details(_action, _changeset, order) do
    %{
      driver_id: order.driver_id,
      driver_name: entregador(order),
      delivery_status: to_string(order.delivery_status),
      delivery_address: order.delivery_address
    }
  end

  # O nome do entregador é lido aqui, e não recebido pronto, porque as três
  # ações de entrega mexem em `driver_id` de formas diferentes — despachar
  # define, reabrir limpa — e o log quer o estado final.
  defp entregador(%{driver_id: nil}), do: "ninguém"

  defp entregador(%{driver_id: driver_id}) do
    case Ash.get(Core.Accounts.User, driver_id, authorize?: false) do
      {:ok, driver} -> driver.name
      _error -> "entregador removido"
    end
  end

  defp cliente(%{customer_name: nil}), do: nil
  defp cliente(%{customer_name: name}), do: "cliente #{name}"

  defp entrega(%{delivery_status: :not_required}), do: "retirada no balcão"
  defp entrega(%{delivery_address: nil}), do: nil
  defp entrega(%{delivery_address: address}), do: "entrega em #{address}"

  defp plural(1), do: "item"
  defp plural(_count), do: "itens"

  defp juntar(partes), do: partes |> Enum.reject(&is_nil/1) |> Enum.join(" — ")
end
