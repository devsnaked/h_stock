defmodule Core.DriverTest do
  @moduledoc """
  O caminho do pedido depois de pronto: balcão manda para um entregador, o
  entregador marca a saída e a chegada.

  O que se testa aqui é sobretudo quem **não** pode: o entregador é o perfil
  com menos alcance do sistema, e é fácil um `authorize_if` a mais devolver a
  loja inteira para ele.
  """
  use Core.DataCase, async: true

  import Core.Fixtures

  alias Core.Accounts.User
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

  describe "perfil do entregador" do
    test "não registra venda" do
      driver = driver_fixture()
      product = product_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Orders.register_order(%{items: [sale_item(product, 100)]}, actor: driver)
    end

    test "virar entregador apaga as permissões de balcão" do
      user =
        user_fixture(
          can_manage_stock: true,
          can_manage_orders: true,
          can_view_dashboard: true,
          dashboard_sections: :all
        )

      {:ok, user} =
        User.set_permissions(
          user,
          %{
            role: :driver,
            can_manage_stock: true,
            can_manage_orders: true,
            can_view_dashboard: true,
            dashboard_sections: [:sales]
          },
          authorize?: false
        )

      refute user.can_manage_stock
      refute user.can_manage_orders
      # O painel também é permissão de balcão: entregador não analisa a loja.
      refute user.can_view_dashboard
      assert user.dashboard_sections == []
    end
  end

  describe "despacho" do
    test "manda o pedido para o entregador sem tirá-lo da fila" do
      employee = user_fixture()
      driver = driver_fixture()
      order = order_fixture(employee)

      {:ok, order} = Orders.assign_driver(order, driver.id, actor: employee)

      assert order.driver_id == driver.id
      assert order.assigned_at
      # Continua `:pending`: quem diz que saiu é quem está com a mercadoria.
      assert order.delivery_status == :pending
    end

    test "não manda para quem não é entregador" do
      employee = user_fixture()
      colega = user_fixture()
      order = order_fixture(employee)

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.assign_driver(order, colega.id, actor: employee)
    end

    test "não manda para entregador desativado" do
      employee = user_fixture()
      driver = driver_fixture()
      {:ok, driver} = User.set_active(driver, false, authorize?: false)
      order = order_fixture(employee)

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.assign_driver(order, driver.id, actor: employee)
    end

    test "não troca o entregador depois de o pedido sair" do
      employee = user_fixture()
      driver = driver_fixture()
      outro = driver_fixture()
      order = order_fixture(employee)

      {:ok, order} = Orders.assign_driver(order, driver.id, actor: employee)
      {:ok, order} = Orders.mark_out_for_delivery(order, actor: employee)

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.assign_driver(order, outro.id, actor: employee)
    end

    test "entregador não despacha pedido" do
      employee = user_fixture()
      driver = driver_fixture()
      outro = driver_fixture()
      order = order_fixture(employee)

      {:ok, order} = Orders.assign_driver(order, driver.id, actor: employee)

      assert {:error, %Ash.Error.Forbidden{}} =
               Orders.assign_driver(order, outro.id, actor: driver)
    end

    test "reabrir devolve o pedido à fila sem dono" do
      employee = user_fixture()
      driver = driver_fixture()
      order = order_fixture(employee)

      {:ok, order} = Orders.assign_driver(order, driver.id, actor: employee)
      {:ok, order} = Orders.mark_out_for_delivery(order, actor: employee)
      {:ok, order} = Orders.reopen_delivery(order, actor: employee)

      refute order.driver_id
      refute order.assigned_at
      assert order.delivery_status == :pending
    end
  end

  describe "entregador escolhido na hora da venda" do
    test "o pedido já nasce com dono" do
      employee = user_fixture()
      driver = driver_fixture()
      product = product_fixture(stock_grams: 5_000)

      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 100)], driver_id: driver.id},
          actor: employee
        )

      assert order.driver_id == driver.id
      assert order.assigned_at
      # Continua na fila: nascer com dono não é ter saído.
      assert order.delivery_status == :pending
      assert [encontrado] = Orders.list_for_driver!(driver.id, actor: driver)
      assert encontrado.id == order.id
    end

    test "sem entregador o pedido nasce na fila, sem dono" do
      employee = user_fixture()
      product = product_fixture(stock_grams: 5_000)

      {:ok, order} =
        Orders.register_order(%{items: [sale_item(product, 100)]}, actor: employee)

      refute order.driver_id
      refute order.assigned_at
    end

    test "retirada no balcão recusa entregador" do
      employee = user_fixture()
      driver = driver_fixture()
      product = product_fixture(stock_grams: 5_000)

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.register_order(
                 %{
                   items: [sale_item(product, 100)],
                   delivery_status: :not_required,
                   driver_id: driver.id
                 },
                 actor: employee
               )
    end

    test "quem não é entregador é recusado na venda" do
      employee = user_fixture()
      colega = user_fixture()
      product = product_fixture(stock_grams: 5_000)

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.register_order(
                 %{items: [sale_item(product, 100)], driver_id: colega.id},
                 actor: employee
               )
    end
  end

  describe "o que o entregador alcança" do
    test "vê e entrega o pedido que está com ele" do
      employee = user_fixture()
      driver = driver_fixture()
      order = order_fixture(employee)

      {:ok, order} = Orders.assign_driver(order, driver.id, actor: employee)

      assert [encontrado] = Orders.list_for_driver!(driver.id, actor: driver)
      assert encontrado.id == order.id

      {:ok, order} = Orders.mark_out_for_delivery(order, actor: driver)
      {:ok, order} = Orders.mark_delivered(order, actor: driver)

      assert order.delivery_status == :delivered
    end

    test "não enxerga pedido que não é dele" do
      employee = user_fixture()
      driver = driver_fixture()
      outro = driver_fixture()
      order = order_fixture(employee)

      {:ok, order} = Orders.assign_driver(order, outro.id, actor: employee)

      assert {:error, _} = Ash.get(Core.Orders.Order, order.id, actor: driver)
      assert [] = Orders.list_for_driver!(driver.id, actor: driver)
    end

    test "não mexe na entrega de pedido de outro entregador" do
      employee = user_fixture()
      driver = driver_fixture()
      outro = driver_fixture()
      order = order_fixture(employee)

      {:ok, order} = Orders.assign_driver(order, outro.id, actor: employee)

      assert {:error, %Ash.Error.Forbidden{}} =
               Orders.mark_delivered(order, actor: driver)
    end

    test "não cancela venda" do
      employee = user_fixture()
      driver = driver_fixture()
      order = order_fixture(employee)

      {:ok, order} = Orders.assign_driver(order, driver.id, actor: employee)

      assert {:error, %Ash.Error.Forbidden{}} = Orders.cancel_order(order, %{}, actor: driver)
    end

    test "a lista da equipe mostra só a própria conta" do
      driver = driver_fixture()
      _colega = user_fixture()

      assert [encontrado] = Ash.read!(User, actor: driver)
      assert encontrado.id == driver.id
    end
  end

  describe "permissão de gerenciar pedidos" do
    test "sem ela o funcionário não enxerga o pedido do colega" do
      autor = user_fixture()
      colega = user_fixture()
      order = order_fixture(autor)

      assert {:error, _} = Ash.get(Core.Orders.Order, order.id, actor: colega)
    end

    test "com ela o funcionário vê, despacha e cancela o pedido do colega" do
      autor = user_fixture()
      gerente = user_fixture(can_manage_orders: true)
      driver = driver_fixture()
      order = order_fixture(autor)

      assert {:ok, order} = Ash.get(Core.Orders.Order, order.id, actor: gerente)
      assert {:ok, order} = Orders.assign_driver(order, driver.id, actor: gerente)
      assert {:ok, order} = Orders.cancel_order(order, %{}, actor: gerente)
      assert order.status == :cancelled
    end
  end
end
