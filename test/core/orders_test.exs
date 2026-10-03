defmodule Core.OrdersTest do
  use Core.DataCase, async: true

  import Core.Fixtures

  alias Core.Inventory.Product
  alias Core.Orders

  defp stock_of(product), do: Ash.get!(Product, product.id, authorize?: false).stock_grams

  defp a_prazo(actor, product, attrs \\ %{}) do
    Orders.register_order(
      Map.merge(
        %{
          items: [sale_item(product, 100)],
          customer_name: "Dona Marta",
          payment_due_on: Date.add(Core.Clock.today(), 15)
        },
        attrs
      ),
      actor: actor
    )
  end

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

  describe "venda a prazo" do
    setup do
      %{employee: user_fixture(), product: product_fixture(stock_grams: 10_000)}
    end

    test "nasce em aberto com o dia combinado", %{employee: employee, product: product} do
      due = Date.add(Core.Clock.today(), 15)
      {:ok, order} = a_prazo(employee, product)

      assert order.payment_due_on == due
      assert order.paid_at == nil
    end

    test "vencimento hoje é aceito; ontem, não", %{employee: employee, product: product} do
      today = Core.Clock.today()

      assert {:ok, _order} = a_prazo(employee, product, %{payment_due_on: today})

      assert {:error, %Ash.Error.Invalid{} = error} =
               a_prazo(employee, product, %{payment_due_on: Date.add(today, -1)})

      assert Exception.message(error) =~ "não pode ser no passado"
      # A venda recusada não pode ter dado baixa no estoque.
      assert Decimal.equal?(stock_of(product), 9_900)
    end

    test "a prazo sem cliente é recusado; à vista, não", %{employee: employee, product: product} do
      assert {:error, %Ash.Error.Invalid{} = error} =
               a_prazo(employee, product, %{customer_name: nil})

      assert Exception.message(error) =~ "nome do cliente"

      assert {:ok, _order} =
               Orders.register_order(%{items: [sale_item(product, 100)]}, actor: employee)
    end

    test "dar baixa marca o pagamento uma vez só", %{employee: employee, product: product} do
      {:ok, order} = a_prazo(employee, product)

      {:ok, paid} = Orders.mark_paid(order, actor: employee)
      assert paid.paid_at

      assert {:error, %Ash.Error.Invalid{} = error} = Orders.mark_paid(paid, actor: employee)
      assert Exception.message(error) =~ "já está pago"
    end

    test "venda à vista e venda cancelada não têm o que receber", %{
      employee: employee,
      product: product
    } do
      {:ok, cash} = Orders.register_order(%{items: [sale_item(product, 100)]}, actor: employee)
      assert {:error, %Ash.Error.Invalid{}} = Orders.mark_paid(cash, actor: employee)

      {:ok, order} = a_prazo(employee, product)
      {:ok, cancelled} = Orders.cancel_order(order, %{}, actor: employee)
      assert {:error, %Ash.Error.Invalid{}} = Orders.mark_paid(cancelled, actor: employee)
    end

    test "quem dá baixa é o balcão que alcança o pedido", %{employee: employee, product: product} do
      driver = driver_fixture()
      {:ok, order} = a_prazo(employee, product)
      {:ok, order} = Orders.assign_driver(order, driver.id, actor: employee)

      assert {:error, %Ash.Error.Forbidden{}} = Orders.mark_paid(order, actor: user_fixture())
      assert {:error, %Ash.Error.Forbidden{}} = Orders.mark_paid(order, actor: driver)

      gerente = user_fixture(can_manage_orders: true)
      assert {:ok, _paid} = Orders.mark_paid(order, actor: gerente)
    end

    test "vencido é passar do dia sem pagar, no dia da loja", %{
      employee: employee,
      product: product
    } do
      {:ok, order} = a_prazo(employee, product)
      due = order.payment_due_on

      refute Orders.overdue?(order, due)
      assert Orders.overdue?(order, Date.add(due, 1))

      {:ok, paid} = Orders.mark_paid(order, actor: employee)
      refute Orders.overdue?(paid, Date.add(due, 1))
    end
  end

  describe "edição" do
    setup do
      %{employee: user_fixture(), product: product_fixture(stock_grams: 10_000)}
    end

    test "corrige cliente e observação e marca quem editou", %{
      employee: employee,
      product: product
    } do
      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 100)], customer_name: "Dona Marta"},
          actor: employee
        )

      gerente = user_fixture(can_manage_orders: true)

      {:ok, edited} =
        Orders.edit_order(order, %{customer_name: "Dona Rita", note: "portão azul"},
          actor: gerente
        )

      assert edited.customer_name == "Dona Rita"
      assert edited.note == "portão azul"
      assert edited.edited_by_id == gerente.id
      assert edited.edited_at
      # Venda e estoque não se mexem.
      assert Decimal.equal?(edited.total, order.total)
      assert Decimal.equal?(stock_of(product), 9_900)
    end

    test "salvar sem mudar nada não marca o pedido como editado", %{
      employee: employee,
      product: product
    } do
      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 100)], customer_name: "Dona Marta"},
          actor: employee
        )

      {:ok, same} = Orders.edit_order(order, %{customer_name: "Dona Marta"}, actor: employee)
      assert same.edited_at == nil
      assert same.edited_by_id == nil
    end

    test "à vista vira a prazo, com as regras do registro", %{
      employee: employee,
      product: product
    } do
      {:ok, order} = Orders.register_order(%{items: [sale_item(product, 100)]}, actor: employee)
      due = Date.add(Core.Clock.today(), 10)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Orders.edit_order(order, %{payment_due_on: due}, actor: employee)

      assert Exception.message(error) =~ "nome do cliente"

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.edit_order(
                 order,
                 %{customer_name: "Seu Zé", payment_due_on: Date.add(Core.Clock.today(), -1)},
                 actor: employee
               )

      {:ok, credit} =
        Orders.edit_order(order, %{customer_name: "Seu Zé", payment_due_on: due}, actor: employee)

      assert credit.payment_due_on == due
    end

    test "conta vencida continua editável sem mexer no vencimento", %{
      employee: employee,
      product: product
    } do
      {:ok, order} = a_prazo(employee, product)
      vencido = Date.add(Core.Clock.today(), -5)

      Core.Repo.query!("update orders set payment_due_on = ? where id = ?", [
        Date.to_iso8601(vencido),
        order.id
      ])

      order = Ash.get!(Orders.Order, order.id, authorize?: false)

      assert {:ok, edited} =
               Orders.edit_order(order, %{note: "ligar antes", payment_due_on: vencido},
                 actor: employee
               )

      assert edited.payment_due_on == vencido
    end

    test "conta paga não troca a forma de pagamento", %{employee: employee, product: product} do
      {:ok, order} = a_prazo(employee, product)
      {:ok, paid} = Orders.mark_paid(order, actor: employee)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Orders.edit_order(paid, %{payment_due_on: nil}, actor: employee)

      assert Exception.message(error) =~ "não muda mais"
    end

    test "retirada não ganha endereço; cancelado não se edita", %{
      employee: employee,
      product: product
    } do
      {:ok, pickup} =
        Orders.register_order(
          %{items: [sale_item(product, 100)], delivery_status: :not_required},
          actor: employee
        )

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.edit_order(pickup, %{delivery_address: "Rua A, 1"}, actor: employee)

      {:ok, cancelled} = Orders.cancel_order(pickup, %{}, actor: employee)

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.edit_order(cancelled, %{note: "x"}, actor: employee)
    end

    test "colega sem permissão e entregador não editam", %{employee: employee, product: product} do
      driver = driver_fixture()
      {:ok, order} = Orders.register_order(%{items: [sale_item(product, 100)]}, actor: employee)
      {:ok, order} = Orders.assign_driver(order, driver.id, actor: employee)

      assert {:error, %Ash.Error.Forbidden{}} =
               Orders.edit_order(order, %{note: "x"}, actor: user_fixture())

      assert {:error, %Ash.Error.Forbidden{}} =
               Orders.edit_order(order, %{note: "x"}, actor: driver)
    end
  end

  describe "edição dos itens" do
    setup do
      employee = user_fixture()

      cafe =
        product_fixture(
          name: "Café",
          price_per_gram: "0.10",
          stock_grams: 1_000,
          cost_per_gram: "0.04"
        )

      cha =
        product_fixture(
          name: "Chá",
          price_per_gram: "0.20",
          stock_grams: 1_000,
          cost_per_gram: "0.05"
        )

      {:ok, order} =
        Orders.register_order(
          %{
            items: [sale_item(cafe, 300), sale_item(cha, 100)],
            discount_type: :percent,
            discount_value: 10
          },
          actor: employee
        )

      order = Ash.load!(order, :items, authorize?: false)
      %{employee: employee, cafe: cafe, cha: cha, order: order}
    end

    defp line(order, product), do: Enum.find(order.items, &(&1.product_id == product.id))

    defp remaining(batch),
      do: Ash.get!(Core.Inventory.Batch, batch.id, authorize?: false).remaining_grams

    test "muda peso, tira e inclui; estoque, totais e desconto acompanham", %{
      employee: employee,
      cafe: cafe,
      cha: cha,
      order: order
    } do
      canela = product_fixture(name: "Canela", price_per_gram: "0.30", stock_grams: 1_000)

      # O café sobe de preço depois da venda: a linha dele continua com o
      # preço congelado. A canela entra com o preço de agora.
      {:ok, _} =
        Core.Inventory.update_product(cafe, %{price_per_gram: Decimal.new("0.50")},
          authorize?: false
        )

      {:ok, edited} =
        Orders.edit_order(
          order,
          %{items: [%{id: line(order, cafe).id, grams: 500}, sale_item(canela, 100)]},
          actor: employee
        )

      edited = Ash.load!(edited, :items, authorize?: false)

      assert Decimal.equal?(remaining(batch_of(cafe)), 500)
      assert Decimal.equal?(remaining(batch_of(cha)), 1_000)
      assert Decimal.equal?(remaining(batch_of(canela)), 900)

      assert Decimal.equal?(line(edited, cafe).grams, 500)
      assert Decimal.equal?(line(edited, cafe).price_per_gram, "0.10")
      assert Decimal.equal?(line(edited, cafe).total, "50.00")
      assert line(edited, cha) == nil
      assert Decimal.equal?(line(edited, canela).total, "30.00")

      # 50 + 30 = 80, menos 10%.
      assert Decimal.equal?(edited.subtotal, "80.00")
      assert Decimal.equal?(edited.discount_total, "8.00")
      assert Decimal.equal?(edited.total, "72.00")
      # Custo: 500 × 0,04 + 100 × 0,02.
      assert Decimal.equal?(edited.cost_total, "22.00")
      assert edited.edited_by_id == employee.id

      # Cancelar depois devolve o que o pedido tem agora, não o que tinha.
      {:ok, _} = Orders.cancel_order(edited, %{}, actor: employee)
      assert Decimal.equal?(remaining(batch_of(cafe)), 1_000)
      assert Decimal.equal?(remaining(batch_of(canela)), 1_000)
    end

    test "o mesmo lote incluído de novo soma na linha que já existe", %{
      employee: employee,
      cafe: cafe,
      cha: cha,
      order: order
    } do
      {:ok, edited} =
        Orders.edit_order(
          order,
          %{
            items: [
              %{id: line(order, cafe).id, grams: 300},
              sale_item(cafe, 200),
              %{id: line(order, cha).id, grams: 100}
            ]
          },
          actor: employee
        )

      edited = Ash.load!(edited, :items, authorize?: false)
      assert length(edited.items) == 2
      assert Decimal.equal?(line(edited, cafe).grams, 500)
      assert Decimal.equal?(remaining(batch_of(cafe)), 500)
    end

    test "sem saldo no lote, nada muda", %{employee: employee, cafe: cafe, order: order} do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Orders.edit_order(order, %{items: [%{id: line(order, cafe).id, grams: 1_200}]},
                 actor: employee
               )

      assert Exception.message(error) =~ "estoque insuficiente"
      reloaded = Ash.get!(Orders.Order, order.id, authorize?: false, load: :items)
      assert length(reloaded.items) == 2
      assert Decimal.equal?(reloaded.total, order.total)
      assert Decimal.equal?(remaining(batch_of(cafe)), 700)
    end

    test "pedido não fica sem item, e conta paga não muda de valor", %{
      employee: employee,
      cafe: cafe
    } do
      {:ok, order} =
        Orders.register_order(
          %{
            items: [sale_item(cafe, 100)],
            customer_name: "Zé",
            payment_due_on: Core.Clock.today()
          },
          actor: employee
        )

      order = Ash.load!(order, :items, authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.edit_order(order, %{items: []}, actor: employee)

      {:ok, paid} = Orders.mark_paid(order, actor: employee)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Orders.edit_order(paid, %{items: [%{id: hd(order.items).id, grams: 200}]},
                 actor: employee
               )

      assert Exception.message(error) =~ "itens não mudam"

      # Mandar os mesmos itens de volta não é mudança: a conta paga continua
      # editável no resto.
      assert {:ok, _} =
               Orders.edit_order(
                 paid,
                 %{note: "ok", items: [%{id: hd(order.items).id, grams: 100}]},
                 actor: employee
               )
    end

    test "o log diz o que mudou nos itens e guarda as linhas de antes", %{
      employee: employee,
      cafe: cafe,
      order: order
    } do
      admin = admin_fixture()

      {:ok, _} =
        Orders.edit_order(order, %{items: [%{id: line(order, cafe).id, grams: 200}]},
          actor: employee
        )

      entry =
        Core.Audit.Entry
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(1)
        |> Ash.read_one!(actor: admin)

      assert entry.action == :order_updated
      assert entry.summary =~ "Café (Lote inicial): 300g → 200g"
      assert entry.summary =~ "Item removido: Chá (Lote inicial), 100g"
      assert entry.summary =~ "Total alterado de R$ 45,00 para R$ 18,00"

      antes = entry.details["antes"] || entry.details[:antes]
      itens = antes["items"] || antes[:items]
      assert length(itens) == 2
    end
  end

  test "código do pedido é estável e legível" do
    id = "7914e4b5-1946-4799-87bc-7cce5da9bfa3"
    assert Orders.code(id) == "7914E4"
    assert Orders.code(%{id: id}) == Orders.code(id)
  end
end
