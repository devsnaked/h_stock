defmodule Core.Orders do
  @moduledoc """
  Pedidos registrados pelos funcionários.

  Um pedido é uma **venda**: ao ser registrado, ele já dá baixa no lote
  escolhido de cada item (e o cancelamento devolve ao mesmo lote). Preço e
  nome do produto, nome e custo do lote ficam gravados no item — mudar o
  preço do produto depois não reescreve o histórico, e o lucro do pedido
  continua sendo o daquele dia.

  O desconto é um só, no pedido inteiro, em porcentagem ou em reais.

  A venda pode ser **à vista** (paga no balcão) ou **a prazo**: nasce com o
  dia combinado (`payment_due_on`) e fica em aberto até alguém do balcão dar
  baixa (`mark_paid/2`). Ver `overdue?/2`.
  """
  use Ash.Domain, otp_app: :h_stock

  resources do
    resource Core.Orders.Order do
      define :list_orders, action: :read
      define :get_order, action: :read, get_by: [:id]
      define :list_to_deliver, action: :to_deliver
      define :list_for_driver, action: :for_driver, args: [:driver_id]
      define :register_order, action: :register
      define :cancel_order, action: :cancel
      define :assign_driver, action: :assign_driver, args: [:driver_id]
      define :mark_out_for_delivery, action: :mark_out_for_delivery
      define :mark_delivered, action: :mark_delivered
      define :reopen_delivery, action: :reopen_delivery
      define :mark_paid, action: :mark_paid
      define :edit_order, action: :edit
    end

    resource Core.Orders.OrderItem
  end

  @doc """
  Código curto e legível do pedido, para o funcionário citar no balcão.

  Deriva do id (não é uma coluna): o mesmo pedido sempre gera o mesmo código.
  """
  @spec code(Core.Orders.Order.t() | String.t()) :: String.t()
  def code(%{id: id}), do: code(id)

  def code(id) when is_binary(id) do
    id
    |> String.replace("-", "")
    |> String.slice(0, 6)
    |> String.upcase()
  end

  @doc """
  Venda a prazo que passou do dia combinado sem ser paga.

  O "hoje" é o da loja (`Core.Clock`): uma conta que vence hoje não está
  vencida às 22h de São Paulo só porque em UTC já é amanhã. Pedido cancelado
  não deve nada, e por isso nunca está vencido.
  """
  @spec overdue?(Core.Orders.Order.t(), Date.t()) :: boolean()
  def overdue?(order, today \\ Core.Clock.today())

  def overdue?(%{status: :completed, payment_due_on: %Date{} = due, paid_at: nil}, today),
    do: Date.before?(due, today)

  def overdue?(_order, _today), do: false
end
