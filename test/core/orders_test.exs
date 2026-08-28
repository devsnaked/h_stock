defmodule Core.OrdersTest do
  use Core.DataCase, async: true

  import Core.Fixtures

  alias Core.Inventory.Product
  alias Core.Orders

  defp stock_of(product), do: Ash.get!(Product, product.id, authorize?: false).stock_grams

  describe "registro do pedido" do
    test "calcula item, subtotal e total, e dá baixa no estoque" do
      employee = user_fixture()
      product = product_fixture(price_per_gram: "0.06", stock_grams: 5_000)

      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 500)]},
          actor: employee
        )

      order = Ash.load!(order, :items, actor: employee)

      assert Decimal.equal?(order.subtotal, "30.00")
      assert Decimal.equal?(order.discount_total, 0)
      assert Decimal.equal?(order.total, "30.00")
      assert Decimal.equal?(stock_of(product), 4_500)

      assert [item] = order.items
      assert item.product_name == product.name
      assert Decimal.equal?(item.price_per_gram, "0.06")
      assert Decimal.equal?(item.total, "30.00")
    end

    test "desconto percentual sai do subtotal" do
      employee = user_fixture()
      product = product_fixture(price_per_gram: "0.10", stock_grams: 5_000)

      {:ok, order} =
        Orders.register_order(
          %{
            items: [sale_item(product, 1_000)],
            discount_type: :percent,
            discount_value: Decimal.new(15)
          },
          actor: employee
        )

      assert Decimal.equal?(order.subtotal, "100.00")
      assert Decimal.equal?(order.discount_total, "15.00")
      assert Decimal.equal?(order.total, "85.00")
    end

    test "desconto em reais nunca passa do subtotal" do
      employee = user_fixture()
      product = product_fixture(price_per_gram: "0.01", stock_grams: 5_000)

      {:ok, order} =
        Orders.register_order(
          %{
            items: [sale_item(product, 1_000)],
            discount_type: :amount,
            discount_value: Decimal.new(999)
          },
          actor: employee
        )

      assert Decimal.equal?(order.subtotal, "10.00")
      assert Decimal.equal?(order.discount_total, "10.00")
      assert Decimal.equal?(order.total, 0)
    end

    test "o mesmo lote repetido vira um item só" do
      employee = user_fixture()
      product = product_fixture(price_per_gram: "0.02", stock_grams: 5_000)

      {:ok, order} =
        Orders.register_order(
          %{
            items: [
              sale_item(product, 300),
              sale_item(product, 200)
            ]
          },
          actor: employee
        )

      order = Ash.load!(order, :items, actor: employee)

      assert [item] = order.items
      assert Decimal.equal?(item.grams, 500)
      assert Decimal.equal?(stock_of(product), 4_500)
    end

    test "lotes diferentes do mesmo produto viram itens separados" do
      employee = user_fixture()
      product = product_fixture(price_per_gram: "0.06", stock_grams: 1_000, cost_per_gram: "0.02")
      caro = batch_fixture(product, grams: 1_000, cost_per_gram: "0.05", label: "Caro")

      {:ok, order} =
        Orders.register_order(
          %{
            items: [
              sale_item(product, 300),
              sale_item(product, 200, caro)
            ]
          },
          actor: employee
        )

      order = Ash.load!(order, :items, actor: employee)

      assert [barato_item, caro_item] =
               Enum.sort_by(order.items, &Decimal.to_float(&1.grams), :desc)

      assert Decimal.equal?(barato_item.cost_per_gram, "0.02")
      assert Decimal.equal?(barato_item.total_cost, "6.00")
      assert Decimal.equal?(caro_item.cost_per_gram, "0.05")
      assert Decimal.equal?(caro_item.total_cost, "10.00")
      assert caro_item.batch_label == "Caro"

      # Receita 500g × 0,06 = 30; custo 6 + 10 = 16.
      assert Decimal.equal?(order.total, "30.00")
      assert Decimal.equal?(order.cost_total, "16.00")

      order = Ash.load!(order, :profit, actor: employee)
      assert Decimal.equal?(order.profit, "14.00")

      # Cada lote perdeu só o que saiu dele.
      assert [barato, caro] = batches(product)
      assert Decimal.equal?(barato.remaining_grams, 700)
      assert Decimal.equal?(caro.remaining_grams, 800)
    end

    test "desconto sai do lucro, não do custo" do
      employee = user_fixture()
      product = product_fixture(price_per_gram: "0.10", stock_grams: 1_000, cost_per_gram: "0.04")

      {:ok, order} =
        Orders.register_order(
          %{
            items: [sale_item(product, 1_000)],
            discount_type: :percent,
            discount_value: Decimal.new(10)
          },
          actor: employee
        )

      # 100 de venda − 10 de desconto − 40 de custo.
      assert Decimal.equal?(order.total, "90.00")
      assert Decimal.equal?(order.cost_total, "40.00")

      order = Ash.load!(order, :profit, actor: employee)
      assert Decimal.equal?(order.profit, "50.00")
    end

    # Mesma armadilha do estoque: o SQLite faria a subtração em ponto
    # flutuante. 0,07 − 0,05 em float não dá 0,02, e é de um centavo que se
    # trata aqui.
    test "lucro não perde centavo em conta de dízima" do
      employee = user_fixture()
      product = product_fixture(price_per_gram: "0.07", stock_grams: 100, cost_per_gram: "0.05")

      {:ok, order} =
        Orders.register_order(%{items: [sale_item(product, 100)]}, actor: employee)

      assert Decimal.equal?(order.total, "7.00")
      assert Decimal.equal?(order.cost_total, "5.00")

      order = Ash.load!(order, [:profit, items: [:profit]], actor: employee)
      assert Decimal.equal?(order.profit, "2.00")
      assert [item] = order.items
      assert Decimal.equal?(item.profit, "2.00")
    end

    test "custo gravado no item não muda quando o lote seguinte custa outro preço" do
      admin = admin_fixture()
      product = product_fixture(price_per_gram: "0.10", stock_grams: 1_000, cost_per_gram: "0.03")

      {:ok, order} = Orders.register_order(%{items: [sale_item(product, 100)]}, actor: admin)

      batch_fixture(product, grams: 500, cost_per_gram: "0.30")

      order = Ash.load!(order, :items, actor: admin)
      assert [%{cost_per_gram: cost}] = order.items
      assert Decimal.equal?(cost, "0.03")
      assert Decimal.equal?(order.cost_total, "3.00")
    end

    test "venda sem lote é recusada" do
      employee = user_fixture()
      product = product_fixture(stock_grams: 1_000)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Orders.register_order(
                 %{items: [%{product_id: product.id, grams: Decimal.new(100)}]},
                 actor: employee
               )

      assert Exception.message(error) =~ "lote"
      assert Decimal.equal?(stock_of(product), 1_000)
    end

    test "lote sem saldo suficiente recusa o pedido inteiro" do
      employee = user_fixture()
      product = product_fixture(stock_grams: 100)
      cheio = batch_fixture(product, grams: 5_000)

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.register_order(
                 %{items: [sale_item(product, 200)]},
                 actor: employee
               )

      # O produto tinha 5.100g no total, mas não no lote pedido.
      assert Decimal.equal?(stock_of(product), 5_100)

      assert Decimal.equal?(
               Ash.get!(Core.Inventory.Batch, cheio.id, authorize?: false).remaining_grams,
               5_000
             )
    end

    test "preço gravado no item não muda quando o produto muda de preço" do
      admin = admin_fixture()
      product = product_fixture(price_per_gram: "0.10", stock_grams: 5_000)

      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 100)]},
          actor: admin
        )

      {:ok, _} =
        Core.Inventory.update_product(product, %{price_per_gram: Decimal.new("0.99")},
          actor: admin
        )

      order = Ash.load!(order, :items, actor: admin)
      assert [%{price_per_gram: price}] = order.items
      assert Decimal.equal?(price, "0.10")
    end

    test "estoque insuficiente recusa o pedido inteiro" do
      employee = user_fixture()
      ok = product_fixture(stock_grams: 1_000)
      curto = product_fixture(stock_grams: 10)

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.register_order(
                 %{
                   items: [
                     sale_item(ok, 100),
                     sale_item(curto, 50)
                   ]
                 },
                 actor: employee
               )

      assert Decimal.equal?(stock_of(ok), 1_000)
      assert Decimal.equal?(stock_of(curto), 10)
    end

    test "produto inativo não pode ser vendido" do
      admin = admin_fixture()
      product = product_fixture(stock_grams: 1_000)
      {:ok, product} = Core.Inventory.update_product(product, %{active: false}, actor: admin)

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.register_order(
                 %{items: [sale_item(product, 10)]},
                 actor: admin
               )
    end
  end

  describe "cancelamento" do
    test "devolve os itens ao estoque e marca o pedido" do
      employee = user_fixture()
      product = product_fixture(stock_grams: 1_000)

      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 400)]},
          actor: employee
        )

      assert Decimal.equal?(stock_of(product), 600)

      {:ok, order} = Orders.cancel_order(order, %{reason: "cliente desistiu"}, actor: employee)

      assert order.status == :cancelled
      assert order.cancelled_at
      assert Decimal.equal?(stock_of(product), 1_000)
    end

    test "a mercadoria volta para o lote de onde saiu, com o custo dela" do
      employee = user_fixture()
      product = product_fixture(stock_grams: 1_000, cost_per_gram: "0.02")
      caro = batch_fixture(product, grams: 500, cost_per_gram: "0.07")

      {:ok, order} =
        Orders.register_order(%{items: [sale_item(product, 500, caro)]}, actor: employee)

      assert [_barato, caro_depois] = batches(product)
      assert Decimal.equal?(caro_depois.remaining_grams, 0)
      assert caro_depois.depleted_at

      {:ok, _order} = Orders.cancel_order(order, %{}, actor: employee)

      # Cancelamento não inventa lote novo nem mercadoria sem custo.
      assert [barato, caro_devolvido] = batches(product)
      assert Decimal.equal?(barato.remaining_grams, 1_000)
      assert Decimal.equal?(caro_devolvido.remaining_grams, 500)
      assert Decimal.equal?(caro_devolvido.cost_per_gram, "0.07")
      refute caro_devolvido.depleted_at
    end

    test "cancelar duas vezes é recusado" do
      employee = user_fixture()
      product = product_fixture(stock_grams: 1_000)

      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 100)]},
          actor: employee
        )

      {:ok, order} = Orders.cancel_order(order, %{}, actor: employee)

      assert {:error, %Ash.Error.Invalid{}} = Orders.cancel_order(order, %{}, actor: employee)
      assert Decimal.equal?(stock_of(product), 1_000)
    end

    test "funcionário não cancela pedido de outro" do
      dono = user_fixture()
      outro = user_fixture()
      product = product_fixture(stock_grams: 1_000)

      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 100)]},
          actor: dono
        )

      assert {:error, %Ash.Error.Forbidden{}} = Orders.cancel_order(order, %{}, actor: outro)
    end
  end

  describe "visibilidade" do
    setup do
      product = product_fixture(stock_grams: 10_000)
      autor = user_fixture()
      outro = user_fixture()
      admin = admin_fixture()

      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 100)]},
          actor: autor
        )

      %{order: order, autor: autor, outro: outro, admin: admin}
    end

    test "admin vê todos os pedidos", %{order: order, admin: admin} do
      assert order.id in Enum.map(Orders.list_orders!(actor: admin), & &1.id)
    end

    test "funcionário vê os seus", %{order: order, autor: autor} do
      assert order.id in Enum.map(Orders.list_orders!(actor: autor), & &1.id)
    end

    test "funcionário não vê o do colega", %{order: order, outro: outro} do
      refute order.id in Enum.map(Orders.list_orders!(actor: outro), & &1.id)
    end
  end

  test "código do pedido é estável e legível" do
    id = "7914e4b5-1946-4799-87bc-7cce5da9bfa3"
    assert Orders.code(id) == "7914E4"
    assert Orders.code(%{id: id}) == Orders.code(id)
  end
end
