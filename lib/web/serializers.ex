defmodule Web.Serializers do
  @moduledoc """
  Converte structs do domínio em mapas prontos para virar props.

  Duas razões para existir: `Decimal` não é serializável em JSON, e o front
  não deve receber campo nenhum que não vá usar. As chaves saem em
  snake_case — o Inertia cameliza sozinho (`camelize_props: true`).

  **Custo e lucro só saem com `costs: true`**, que os controllers passam
  quando quem está olhando gerencia estoque. O funcionário comum precisa dos
  lotes para escolher de qual vende, mas não do quanto a loja pagou por eles —
  e o jeito de garantir isso é o campo não sair daqui.
  """

  alias Core.Accounts.Permissions
  alias Core.Orders

  def product(product, opts \\ [])
  def product(nil, _opts), do: nil

  def product(product, opts) do
    base = %{
      id: product.id,
      name: product.name,
      unit: product.unit,
      price_per_gram: number(product.price_per_gram),
      price_per_kg: number(Decimal.mult(product.price_per_gram, 1000)),
      stock_grams: number(product.stock_grams),
      min_stock_grams: number(product.min_stock_grams),
      low_stock: not Decimal.gt?(product.stock_grams, product.min_stock_grams),
      active: product.active
    }

    # O valor em estoque só existe quando o controller carregou o agregado; a
    # chave não sai à toa para não virar `null` na tela.
    case costs?(opts) and loaded_value(product, :stock_cost_value, nil) do
      %Decimal{} = value -> Map.put(base, :stock_cost_value, number(value))
      _ -> base
    end
  end

  @doc """
  Lote de estoque. Sem `costs: true` sai só o que a venda precisa: nome e
  quanto ainda há.
  """
  def batch(batch, opts \\ [])
  def batch(nil, _opts), do: nil

  def batch(batch, opts) do
    base = %{
      id: batch.id,
      label: batch.label,
      remaining_grams: number(batch.remaining_grams),
      initial_grams: number(batch.initial_grams),
      depleted: not Decimal.positive?(batch.remaining_grams),
      inserted_at: batch.inserted_at,
      user_name: loaded_name(batch, :user)
    }

    if costs?(opts) do
      Map.merge(base, %{
        cost_per_gram: number(batch.cost_per_gram),
        cost_per_kg: number(Decimal.mult(batch.cost_per_gram, 1000)),
        remaining_cost: number(Decimal.mult(batch.remaining_grams, batch.cost_per_gram)),
        total_cost: number(Decimal.mult(batch.initial_grams, batch.cost_per_gram))
      })
    else
      base
    end
  end

  @doc """
  Movimentação do histórico. Só quem gerencia estoque lê `StockMovement`
  (é policy do recurso), então o custo sai sempre.
  """
  def movement(movement) do
    %{
      id: movement.id,
      kind: movement.kind,
      grams: number(movement.grams),
      balance_after: number(movement.balance_after),
      batch_balance_after: number(movement.batch_balance_after),
      cost_per_gram: number(movement.cost_per_gram),
      total_cost: number(movement.total_cost),
      batch_id: movement.batch_id,
      batch_label: loaded_label(movement, :batch),
      reason: movement.reason,
      inserted_at: movement.inserted_at,
      user_name: loaded_name(movement, :user),
      # A venda que gerou esta linha. O código sai do próprio id (é derivado),
      # então mostrar de qual pedido saiu a mercadoria não custa uma consulta.
      order_id: movement.order_id,
      order_code: movement.order_id && Orders.code(movement.order_id)
    }
  end

  def order(order, opts \\ []) do
    base = %{
      id: order.id,
      code: Orders.code(order),
      customer_name: order.customer_name,
      status: order.status,
      subtotal: number(order.subtotal),
      discount_type: order.discount_type,
      discount_value: number(order.discount_value),
      discount_total: number(order.discount_total),
      total: number(order.total),
      inserted_at: order.inserted_at,
      cancelled_at: order.cancelled_at,
      delivery_status: order.delivery_status,
      delivery_address: order.delivery_address,
      delivery_lat: number(order.delivery_lat),
      delivery_lon: number(order.delivery_lon),
      driver_id: order.driver_id,
      driver_name: loaded_name(order, :driver),
      assigned_at: order.assigned_at,
      out_for_delivery_at: order.out_for_delivery_at,
      delivered_at: order.delivered_at,
      user_name: loaded_name(order, :user),
      # Venda a prazo: vencimento e baixa. "Vencido" sai daqui, e não da
      # tela, porque o "hoje" que conta é o da loja, não o do aparelho.
      payment_due_on: order.payment_due_on,
      paid_at: order.paid_at,
      payment_overdue: Orders.overdue?(order)
    }

    base
    # Quem editou é do administrador, como o log de onde vem o histórico: o
    # campo não sai do servidor para mais ninguém.
    |> then(fn base ->
      if Keyword.get(opts, :edits, false) do
        Map.merge(base, %{
          edited_at: order.edited_at,
          edited_by_name: loaded_name(order, :edited_by)
        })
      else
        base
      end
    end)
    |> then(fn base ->
      if costs?(opts) do
        Map.merge(base, %{
          cost_total: number(order.cost_total),
          profit: number(Decimal.sub(order.total, order.cost_total))
        })
      else
        base
      end
    end)
    |> then(fn base ->
      if Keyword.get(opts, :with_items, false) do
        Map.merge(base, %{
          note: order.note,
          items: Enum.map(order.items, &order_item(&1, opts))
        })
      else
        Map.put(base, :items_count, loaded_value(order, :items_count, 0))
      end
    end)
  end

  def order_item(item, opts \\ []) do
    base = %{
      id: item.id,
      product_id: item.product_id,
      product_name: item.product_name,
      grams: number(item.grams),
      price_per_gram: number(item.price_per_gram),
      total: number(item.total),
      batch_id: item.batch_id,
      batch_label: item.batch_label
    }

    if costs?(opts) do
      Map.merge(base, %{
        cost_per_gram: number(item.cost_per_gram),
        total_cost: number(item.total_cost),
        profit: number(Decimal.sub(item.total, item.total_cost))
      })
    else
      base
    end
  end

  def user(nil), do: nil

  def user(user) do
    %{
      id: user.id,
      name: user.name,
      nickname: to_string(user.nickname),
      role: user.role,
      can_manage_stock: user.can_manage_stock,
      manages_stock: user.role == :admin or user.can_manage_stock,
      can_manage_orders: user.can_manage_orders,
      manages_orders: user.role == :admin or user.can_manage_orders,
      # `can_view_dashboard`/`dashboard_sections` saem crus, como estão
      # guardados: é deles que o formulário de permissões parte. `views_dashboard`
      # é o efetivo (o admin entra sem chave), e é o que a navegação checa para
      # mostrar ou não o item do painel.
      can_view_dashboard: user.can_view_dashboard,
      views_dashboard: Permissions.views_dashboard?(user),
      dashboard_sections: user.dashboard_sections,
      active: user.active,
      two_factor: user.totp_confirmed_at != nil,
      inserted_at: user.inserted_at
    }
  end

  @doc """
  Entregador na hora de escolher para quem mandar o pedido. Só nome e login —
  a tela não precisa (nem deve) receber o resto do cadastro da pessoa.
  """
  def driver(user) do
    %{id: user.id, name: user.name, nickname: to_string(user.nickname)}
  end

  defp costs?(opts), do: Keyword.get(opts, :costs, false)

  # Decimal -> float. As casas decimais que importam (2 para dinheiro) já
  # foram arredondadas no domínio; aqui é só transporte.
  @doc """
  Uma linha do log de auditoria.

  O nome de quem agiu sai do campo **congelado** (`user_name`), não do usuário
  relacionado: o log tem de continuar dizendo quem fez a ação mesmo depois de
  a pessoa mudar de nome ou ser desativada. O `user_id` acompanha só para a
  tela filtrar por pessoa.
  """
  def audit_entry(entry) do
    %{
      id: entry.id,
      action: entry.action,
      subject_type: entry.subject_type,
      subject_id: entry.subject_id,
      subject_label: entry.subject_label,
      summary: entry.summary,
      details: entry.details,
      user_id: entry.user_id,
      user_name: entry.user_name,
      inserted_at: entry.inserted_at
    }
  end

  defp number(nil), do: nil
  defp number(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp number(value), do: value

  defp loaded_name(record, key) do
    case Map.get(record, key) do
      %{name: name} -> name
      _ -> nil
    end
  end

  defp loaded_label(record, key) do
    case Map.get(record, key) do
      %{label: label} -> label
      _ -> nil
    end
  end

  defp loaded_value(record, key, default) do
    case Map.get(record, key) do
      %Ash.NotLoaded{} -> default
      nil -> default
      value -> value
    end
  end
end
