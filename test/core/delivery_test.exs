defmodule Core.DeliveryTest do
  use Core.DataCase, async: true

  import Core.Fixtures

  alias Core.Orders

  defp order_fixture(actor, attrs \\ %{}) do
    product = product_fixture(stock_grams: 5_000)

    {:ok, order} =
      Orders.register_order(
        Map.merge(%{items: [sale_item(product, 100)]}, attrs),
        actor: actor
      )

    order
  end

  describe "ciclo da entrega" do
    test "nasce aguardando entrega" do
      order = order_fixture(user_fixture())

      assert order.delivery_status == :pending
      refute order.out_for_delivery_at
      refute order.delivered_at
    end

    test "pode nascer sem entrega (retirada no balcão)" do
      order = order_fixture(user_fixture(), %{delivery_status: :not_required})

      assert order.delivery_status == :not_required
    end

    test "saiu para entrega registra a hora" do
      user = user_fixture()
      order = order_fixture(user)

      {:ok, order} = Orders.mark_out_for_delivery(order, actor: user)

      assert order.delivery_status == :out_for_delivery
      assert order.out_for_delivery_at
    end

    test "entregue registra a hora" do
      user = user_fixture()
      order = order_fixture(user)

      {:ok, order} = Orders.mark_out_for_delivery(order, actor: user)
      {:ok, order} = Orders.mark_delivered(order, actor: user)

      assert order.delivery_status == :delivered
      assert order.delivered_at
    end

    test "dá para marcar entregue sem ter marcado a saída" do
      user = user_fixture()
      order = order_fixture(user)

      {:ok, order} = Orders.mark_delivered(order, actor: user)

      assert order.delivery_status == :delivered
      refute order.out_for_delivery_at
    end

    test "entregar duas vezes é recusado" do
      user = user_fixture()
      order = order_fixture(user)

      {:ok, order} = Orders.mark_delivered(order, actor: user)

      assert {:error, %Ash.Error.Invalid{}} = Orders.mark_delivered(order, actor: user)
    end

    test "sair duas vezes é recusado" do
      user = user_fixture()
      order = order_fixture(user)

      {:ok, order} = Orders.mark_out_for_delivery(order, actor: user)

      assert {:error, %Ash.Error.Invalid{}} = Orders.mark_out_for_delivery(order, actor: user)
    end

    test "reabrir limpa as marcações" do
      user = user_fixture()
      order = order_fixture(user)

      {:ok, order} = Orders.mark_delivered(order, actor: user)
      {:ok, order} = Orders.reopen_delivery(order, actor: user)

      assert order.delivery_status == :pending
      refute order.delivered_at
      refute order.out_for_delivery_at
    end

    test "pedido cancelado não sai para entrega" do
      user = user_fixture()
      order = order_fixture(user)

      {:ok, order} = Orders.cancel_order(order, %{}, actor: user)

      assert {:error, %Ash.Error.Invalid{}} = Orders.mark_out_for_delivery(order, actor: user)
      assert {:error, %Ash.Error.Invalid{}} = Orders.mark_delivered(order, actor: user)
    end
  end

  describe "fila de entrega" do
    test "traz aguardando e a caminho, mas não entregue, retirada ou cancelado" do
      user = admin_fixture()

      aguardando = order_fixture(user)
      a_caminho = order_fixture(user)
      entregue = order_fixture(user)
      retirada = order_fixture(user, %{delivery_status: :not_required})
      cancelado = order_fixture(user)

      {:ok, _} = Orders.mark_out_for_delivery(a_caminho, actor: user)
      {:ok, _} = Orders.mark_delivered(entregue, actor: user)
      {:ok, _} = Orders.cancel_order(cancelado, %{}, actor: user)

      fila = Orders.list_to_deliver!(actor: user) |> Enum.map(& &1.id)

      assert aguardando.id in fila
      assert a_caminho.id in fila
      refute entregue.id in fila
      refute retirada.id in fila
      refute cancelado.id in fila
    end

    test "funcionário só vê a própria fila" do
      autor = user_fixture()
      colega = user_fixture()

      order = order_fixture(autor)

      assert order.id in Enum.map(Orders.list_to_deliver!(actor: autor), & &1.id)
      assert [] = Orders.list_to_deliver!(actor: colega)
    end
  end

  test "funcionário não mexe na entrega de pedido alheio" do
    autor = user_fixture()
    colega = user_fixture()
    order = order_fixture(autor)

    assert {:error, %Ash.Error.Forbidden{}} =
             Orders.mark_out_for_delivery(order, actor: colega)
  end
end
