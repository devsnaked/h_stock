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

  # O que a edição (`:edit`) pode mexer, na ordem em que as mudanças aparecem
  # na frase.
  @editable [
    :customer_name,
    :note,
    :delivery_address,
    :delivery_lat,
    :delivery_lon,
    :payment_due_on
  ]

  @impl true
  def change(changeset, opts, context) do
    case Keyword.fetch!(opts, :action) do
      :order_updated -> log_edit(changeset, context)
      action -> log_event(changeset, action, context)
    end
  end

  defp log_event(changeset, action, context) do
    Ash.Changeset.after_action(changeset, fn changeset, order ->
      Core.Audit.record(action, order, context.actor,
        summary: summary(action, changeset, order),
        details: details(action, changeset, order)
      )

      {:ok, order}
    end)
  end

  # Edição: a linha guarda o pedido **antes** e **depois** (os campos
  # editáveis inteiros e o total; e, quando os itens mudaram, as linhas dos
  # dois momentos), para o registro bastar sozinho mesmo depois de outras
  # edições. A frase diz só o que mudou, de quê para quê. Salvar sem mudar
  # nada não vira linha.
  defp log_edit(changeset, context) do
    Ash.Changeset.after_action(changeset, fn changeset, order ->
      before = changeset.data
      items = changeset.context[:item_plan]
      changed = Enum.reject(@editable, &same?(Map.fetch!(before, &1), Map.fetch!(order, &1)))

      if changed == [] and items == nil do
        {:ok, order}
      else
        Core.Audit.record(:order_updated, order, context.actor,
          summary: edit_summary(changed, before, order, items),
          details: %{
            campos: Enum.map(changed, &to_string/1) ++ if(items, do: ["items"], else: []),
            antes: snapshot(before, items && items.items_before),
            depois: snapshot(order, items && items.items_after)
          }
        )

        {:ok, order}
      end
    end)
  end

  defp edit_summary(changed, before, order, items) do
    fields =
      changed
      |> Enum.flat_map(&sentence(&1, Map.fetch!(before, &1), Map.fetch!(order, &1), changed))
      |> Enum.uniq()

    lines = if items, do: items.sentences, else: []

    total =
      if same?(before.total, order.total),
        do: [],
        else: [
          "Total alterado de #{Core.Audit.money(before.total)} para #{Core.Audit.money(order.total)}"
        ]

    Enum.join(fields ++ lines ++ total, "; ")
  end

  defp sentence(:customer_name, old, new, _changed),
    do: ["Cliente alterado de #{texto(old)} para #{texto(new)}"]

  defp sentence(:note, old, new, _changed),
    do: ["Observação alterada de #{texto(old)} para #{texto(new)}"]

  defp sentence(:delivery_address, old, new, _changed),
    do: ["Endereço alterado de #{texto(old)} para #{texto(new)}"]

  # O ponto acompanha o endereço; sozinho, é alguém acertando o pino no mapa.
  defp sentence(field, _old, _new, changed) when field in [:delivery_lat, :delivery_lon] do
    if :delivery_address in changed, do: [], else: ["Ponto no mapa alterado"]
  end

  defp sentence(:payment_due_on, nil, new, _changed),
    do: ["Passou para a prazo, vence em #{data(new)}"]

  defp sentence(:payment_due_on, old, nil, _changed),
    do: ["Passou para à vista (vencia em #{data(old)})"]

  defp sentence(:payment_due_on, old, new, _changed),
    do: ["Vencimento alterado de #{data(old)} para #{data(new)}"]

  defp snapshot(order, items) do
    @editable
    |> Map.new(fn field ->
      value = Map.fetch!(order, field)
      {field, value && to_string(value)}
    end)
    |> Map.put(:total, to_string(order.total))
    |> then(fn snapshot -> if items, do: Map.put(snapshot, :items, items), else: snapshot end)
  end

  # Coordenada volta do banco como `Decimal`, e "-23.50" e "-23.5" são o
  # mesmo ponto.
  defp same?(%Decimal{} = old, %Decimal{} = new), do: Decimal.equal?(old, new)
  defp same?(old, new), do: old == new

  defp texto(nil), do: "(vazio)"
  defp texto(value), do: ~s("#{value}")

  defp summary(:order_registered, changeset, order) do
    itens = changeset |> Ash.Changeset.get_argument(:items) |> length()

    [
      "Venda de #{Core.Audit.money(order.total)} em #{itens} #{plural(itens)}",
      cliente(order),
      entrega(order),
      prazo(order)
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

  defp summary(:order_paid, _changeset, order) do
    [
      "Pagamento a prazo recebido: #{Core.Audit.money(order.total)}",
      cliente(order),
      "vencia em #{data(order.payment_due_on)}"
    ]
    |> juntar()
  end

  defp details(:order_registered, changeset, order) do
    %{
      total: to_string(order.total),
      subtotal: to_string(order.subtotal),
      discount_total: to_string(order.discount_total),
      cost_total: to_string(order.cost_total),
      items: changeset |> Ash.Changeset.get_argument(:items) |> length(),
      customer_name: order.customer_name,
      delivery_status: to_string(order.delivery_status),
      payment_due_on: order.payment_due_on && Date.to_iso8601(order.payment_due_on)
    }
  end

  defp details(:order_cancelled, changeset, order) do
    %{
      total: to_string(order.total),
      reason: Ash.Changeset.get_argument(changeset, :reason),
      cancelled_at: to_string(order.cancelled_at)
    }
  end

  defp details(:order_paid, _changeset, order) do
    %{
      total: to_string(order.total),
      payment_due_on: Date.to_iso8601(order.payment_due_on),
      paid_at: to_string(order.paid_at)
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

  defp prazo(%{payment_due_on: nil}), do: nil
  defp prazo(%{payment_due_on: date}), do: "a prazo, vence em #{data(date)}"

  defp data(date), do: Calendar.strftime(date, "%d/%m/%Y")

  defp plural(1), do: "item"
  defp plural(_count), do: "itens"

  defp juntar(partes), do: partes |> Enum.reject(&is_nil/1) |> Enum.join(" — ")
end
