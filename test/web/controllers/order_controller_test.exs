defmodule Web.OrderControllerTest do
  use Web.ConnCase, async: true

  import Inertia.Testing
  import Core.Fixtures

  alias Core.Inventory.Product
  alias Core.Orders

  describe "registrar pedido" do
    setup %{conn: conn} do
      employee = user_fixture()

      %{
        conn: log_in(conn, employee),
        employee: employee,
        product: product_fixture(price_per_gram: "0.06", stock_grams: 5_000)
      }
    end

    test "converte kg em gramas e aplica o desconto", %{conn: conn, product: product} do
      conn =
        post(conn, ~p"/pedidos", %{
          "items" => [
            %{
              "product_id" => product.id,
              "batch_id" => batch_of(product).id,
              "quantity" => "1,5",
              "unit" => "kg"
            }
          ],
          "customer_name" => "Seu Zé",
          "discount_type" => "percent",
          "discount_value" => "10"
        })

      assert %{id: id} = redirected_params(conn)
      order = Ash.get!(Orders.Order, id, authorize?: false, load: :items)

      assert [%{grams: grams}] = order.items
      assert Decimal.equal?(grams, 1_500)
      # 1500g x 0,06 = 90,00 - 10% = 81,00
      assert Decimal.equal?(order.subtotal, "90.00")
      assert Decimal.equal?(order.total, "81.00")
      assert order.customer_name == "Seu Zé"

      assert Decimal.equal?(Ash.get!(Product, product.id, authorize?: false).stock_grams, 3_500)
    end

    test "pedido sem itens é recusado", %{conn: conn} do
      conn = post(conn, ~p"/pedidos", %{"items" => []})

      assert redirected_to(conn) == ~p"/pedidos/novo"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "ao menos um produto"
    end

    test "item sem lote é recusado", %{conn: conn, product: product} do
      conn =
        post(conn, ~p"/pedidos", %{
          "items" => [%{"product_id" => product.id, "quantity" => "100", "unit" => "g"}]
        })

      assert redirected_to(conn) == ~p"/pedidos/novo"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "lote"
      assert Decimal.equal?(Ash.get!(Product, product.id, authorize?: false).stock_grams, 5_000)
    end

    test "vender de dois lotes gera dois itens com custos diferentes", %{
      conn: conn,
      product: product
    } do
      caro = batch_fixture(product, grams: 1_000, cost_per_gram: "0.05", label: "Caro")

      conn =
        post(conn, ~p"/pedidos", %{
          "items" => [
            %{
              "product_id" => product.id,
              "batch_id" => batch_of(product).id,
              "quantity" => "100",
              "unit" => "g"
            },
            %{
              "product_id" => product.id,
              "batch_id" => caro.id,
              "quantity" => "100",
              "unit" => "g"
            }
          ]
        })

      assert %{id: id} = redirected_params(conn)
      order = Ash.get!(Orders.Order, id, authorize?: false, load: :items)

      assert [_, _] = order.items
      # 100g a 0,02 + 100g a 0,05 (o fixture entra com 0,02 no lote inicial).
      assert Decimal.equal?(order.cost_total, "7.00")
      assert Enum.all?(order.items, & &1.batch_id)
    end

    test "estoque insuficiente volta com o motivo", %{conn: conn, product: product} do
      conn =
        post(conn, ~p"/pedidos", %{
          "items" => [
            %{
              "product_id" => product.id,
              "batch_id" => batch_of(product).id,
              "quantity" => "50",
              "unit" => "kg"
            }
          ]
        })

      assert redirected_to(conn) == ~p"/pedidos/novo"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "insuficiente"
      assert Decimal.equal?(Ash.get!(Product, product.id, authorize?: false).stock_grams, 5_000)
    end

    test "guarda o endereço e o ponto escolhido no mapa", %{conn: conn, product: product} do
      conn =
        post(conn, ~p"/pedidos", %{
          "items" => [
            %{
              "product_id" => product.id,
              "batch_id" => batch_of(product).id,
              "quantity" => "100",
              "unit" => "g"
            }
          ],
          "delivery_address" => "Rua das Flores, 100 - Centro",
          "delivery_lat" => "-23.55052",
          "delivery_lon" => "-46.633308"
        })

      assert %{id: id} = redirected_params(conn)
      order = Ash.get!(Orders.Order, id, authorize?: false)

      assert order.delivery_address == "Rua das Flores, 100 - Centro"
      assert Decimal.equal?(order.delivery_lat, "-23.55052")
      assert Decimal.equal?(order.delivery_lon, "-46.633308")
    end

    test "a venda já sai com entregador quando o balcão escolhe um", %{
      conn: conn,
      product: product
    } do
      driver = driver_fixture(name: "Joana Correia")

      conn =
        post(conn, ~p"/pedidos", %{
          "items" => [
            %{
              "product_id" => product.id,
              "batch_id" => batch_of(product).id,
              "quantity" => "100",
              "unit" => "g"
            }
          ],
          "delivery_address" => "Rua das Flores, 100",
          "driver_id" => driver.id
        })

      assert %{id: id} = redirected_params(conn)
      order = Ash.get!(Orders.Order, id, authorize?: false)

      assert order.driver_id == driver.id
      # Despachado na venda, mas ainda não saiu: quem marca a saída é quem
      # está com a mercadoria.
      assert order.delivery_status == :pending
      assert order.assigned_at
    end

    test "retirada no balcão não guarda endereço", %{conn: conn, product: product} do
      conn =
        post(conn, ~p"/pedidos", %{
          "items" => [
            %{
              "product_id" => product.id,
              "batch_id" => batch_of(product).id,
              "quantity" => "100",
              "unit" => "g"
            }
          ],
          "needs_delivery" => false,
          "delivery_address" => "Rua das Flores, 100"
        })

      assert %{id: id} = redirected_params(conn)
      order = Ash.get!(Orders.Order, id, authorize?: false)

      assert order.delivery_status == :not_required
      refute order.delivery_address
    end
  end

  describe "tela de novo pedido" do
    test "traz os lotes com saldo de cada produto", %{conn: conn} do
      product = product_fixture(stock_grams: 1_000)
      batch_fixture(product, grams: 500, label: "Segundo lote")

      conn = conn |> log_in(user_fixture()) |> get(~p"/pedidos/novo")

      assert inertia_component(conn) == "Orders/New"
      assert %{products: [%{batches: batches}]} = inertia_props(conn)

      assert ["Lote inicial", "Segundo lote"] = Enum.map(batches, & &1.label)
      # O funcionário precisa do lote para vender, mas não do que ele custou.
      refute Enum.any?(batches, &Map.has_key?(&1, :costPerGram))
    end

    test "lote acabado não aparece para vender", %{conn: conn} do
      admin = admin_fixture()
      product = product_fixture(stock_grams: 1_000)
      vazio = batch_fixture(product, grams: 100, label: "Acabou")

      {:ok, _} =
        Core.Inventory.remove_stock(product, Decimal.new(100), vazio.id, %{}, actor: admin)

      conn = conn |> log_in(admin) |> get(~p"/pedidos/novo")

      assert %{products: [%{batches: batches}]} = inertia_props(conn)
      assert ["Lote inicial"] = Enum.map(batches, & &1.label)
    end
  end

  describe "listagem" do
    setup do
      product = product_fixture(stock_grams: 10_000)
      autor = user_fixture()
      colega = user_fixture()
      admin = admin_fixture()

      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 100)]},
          actor: autor
        )

      %{order: order, autor: autor, colega: colega, admin: admin}
    end

    test "funcionário vê só os próprios pedidos", %{conn: conn, order: order, autor: autor} do
      conn = conn |> log_in(autor) |> get(~p"/pedidos")

      assert inertia_component(conn) == "Orders/Index"
      assert %{orders: [%{id: id}]} = inertia_props(conn)
      assert id == order.id
    end

    test "colega não vê o pedido alheio", %{conn: conn, colega: colega} do
      conn = conn |> log_in(colega) |> get(~p"/pedidos")

      assert %{orders: []} = inertia_props(conn)
    end

    test "admin vê o pedido de todo mundo", %{conn: conn, order: order, admin: admin} do
      conn = conn |> log_in(admin) |> get(~p"/pedidos")

      assert %{orders: [%{id: id}]} = inertia_props(conn)
      assert id == order.id
    end

    test "abrir pedido de outro funcionário devolve para a lista", %{
      conn: conn,
      order: order,
      colega: colega
    } do
      conn = conn |> log_in(colega) |> get(~p"/pedidos/#{order.id}")

      assert redirected_to(conn) == ~p"/pedidos"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "não encontrado"
    end
  end

  describe "busca" do
    setup do
      product = product_fixture(stock_grams: 50_000)
      autor = user_fixture()

      pedido = fn attrs ->
        {:ok, order} =
          Orders.register_order(
            Map.merge(%{items: [sale_item(product, 100)]}, attrs),
            actor: autor
          )

        order
      end

      %{pedido: pedido, autor: autor}
    end

    test "acha pelo nome do cliente", %{conn: conn, pedido: pedido, autor: autor} do
      marta = pedido.(%{customer_name: "Dona Marta"})
      _ze = pedido.(%{customer_name: "Seu Zé"})

      conn = conn |> log_in(autor) |> get(~p"/pedidos?busca=marta")

      assert %{orders: [%{id: id}], search: "marta"} = inertia_props(conn)
      assert id == marta.id
    end

    test "acha pelo endereço e pelo código", %{conn: conn, pedido: pedido, autor: autor} do
      order = pedido.(%{delivery_address: "Rua das Flores, 100 — Centro"})
      conn = log_in(conn, autor)

      assert %{orders: [%{id: achado}]} = inertia_props(get(conn, ~p"/pedidos?busca=flores"))
      assert achado == order.id

      codigo = Orders.code(order)
      assert %{orders: [%{id: achado}]} = inertia_props(get(conn, ~p"/pedidos?busca=#{codigo}"))
      assert achado == order.id
    end

    test "acha pelo entregador", %{conn: conn, pedido: pedido, autor: autor} do
      driver = driver_fixture(name: "Joana Correia")
      order = pedido.(%{customer_name: "Alguém"})
      {:ok, _} = Orders.assign_driver(order, driver.id, actor: autor)
      _outro = pedido.(%{customer_name: "Outro"})

      conn = conn |> log_in(autor) |> get(~p"/pedidos?busca=joana")

      assert %{orders: [%{id: id}]} = inertia_props(conn)
      assert id == order.id
    end

    test "busca sem resultado devolve lista vazia, não erro", %{conn: conn, autor: autor} do
      conn = conn |> log_in(autor) |> get(~p"/pedidos?busca=zzzzz")

      assert %{orders: [], page: %{count: 0}} = inertia_props(conn)
    end

    test "a busca convive com o filtro de entrega", %{conn: conn, pedido: pedido, autor: autor} do
      entregue = pedido.(%{customer_name: "Dona Marta"})
      _na_fila = pedido.(%{customer_name: "Dona Marta"})
      {:ok, _} = Orders.mark_delivered(entregue, actor: autor)

      conn = conn |> log_in(autor) |> get(~p"/pedidos?busca=marta&entrega=entregues")

      assert %{orders: [%{id: id}]} = inertia_props(conn)
      assert id == entregue.id
    end
  end

  describe "paginação" do
    setup do
      product = product_fixture(stock_grams: 100_000)
      autor = user_fixture()

      for _ <- 1..25 do
        {:ok, _} = Orders.register_order(%{items: [sale_item(product, 100)]}, actor: autor)
      end

      %{autor: autor}
    end

    test "a primeira página traz 20 e conta o resto", %{conn: conn, autor: autor} do
      conn = conn |> log_in(autor) |> get(~p"/pedidos")

      assert %{orders: orders, page: page} = inertia_props(conn)
      assert length(orders) == 20
      assert page == %{number: 1, size: 20, count: 25, pages: 2}
    end

    test "a segunda página traz o que sobrou, sem repetir", %{conn: conn, autor: autor} do
      conn = log_in(conn, autor)

      primeira = inertia_props(get(conn, ~p"/pedidos"))
      segunda = inertia_props(get(conn, ~p"/pedidos?pagina=2"))

      assert length(segunda.orders) == 5
      assert segunda.page.number == 2

      ids = fn props -> Enum.map(props.orders, & &1.id) end
      assert ids.(primeira) -- ids.(segunda) == ids.(primeira)
    end

    test "página inválida cai na primeira", %{conn: conn, autor: autor} do
      conn = conn |> log_in(autor) |> get(~p"/pedidos?pagina=abacaxi")

      assert %{page: %{number: 1}} = inertia_props(conn)
    end
  end

  describe "entrega" do
    setup %{conn: conn} do
      employee = user_fixture()
      product = product_fixture(stock_grams: 5_000)

      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 100)]},
          actor: employee
        )

      %{conn: log_in(conn, employee), employee: employee, order: order}
    end

    test "marca saída e entrega", %{conn: conn, order: order} do
      conn = post(conn, ~p"/pedidos/#{order.id}/entrega/saiu")
      assert redirected_to(conn) == ~p"/pedidos/#{order.id}"

      recarregado = Ash.get!(Orders.Order, order.id, authorize?: false)
      assert recarregado.delivery_status == :out_for_delivery
      assert recarregado.out_for_delivery_at

      conn = post(recycle(conn), ~p"/pedidos/#{order.id}/entrega/entregue")
      assert redirected_to(conn) == ~p"/pedidos/#{order.id}"

      recarregado = Ash.get!(Orders.Order, order.id, authorize?: false)
      assert recarregado.delivery_status == :delivered
      assert recarregado.delivered_at
    end

    test "estágio desconhecido não explode", %{conn: conn, order: order} do
      conn = post(conn, ~p"/pedidos/#{order.id}/entrega/voando")

      assert redirected_to(conn) == ~p"/pedidos/#{order.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "inválido"
    end

    test "pedido de outro funcionário não é alcançável", %{order: order} do
      conn =
        build_conn()
        |> log_in(user_fixture())
        |> post(~p"/pedidos/#{order.id}/entrega/saiu")

      assert redirected_to(conn) == ~p"/pedidos"
      assert Ash.get!(Orders.Order, order.id, authorize?: false).delivery_status == :pending
    end

    test "filtro da lista separa a fila", %{conn: conn, order: order, employee: employee} do
      {:ok, _} = Orders.mark_delivered(order, actor: employee)

      conn = get(conn, ~p"/pedidos?entrega=entregues")
      assert %{orders: [%{id: id}], filter: "entregues"} = inertia_props(conn)
      assert id == order.id

      conn = get(recycle(conn), ~p"/pedidos?entrega=pendentes")
      assert %{orders: []} = inertia_props(conn)
    end

    test "pedido de retirada nasce fora da fila", %{conn: conn} do
      product = product_fixture(stock_grams: 1_000)

      conn =
        post(conn, ~p"/pedidos", %{
          "items" => [
            %{
              "product_id" => product.id,
              "batch_id" => batch_of(product).id,
              "quantity" => "100",
              "unit" => "g"
            }
          ],
          "needs_delivery" => false
        })

      assert %{id: id} = redirected_params(conn)
      assert Ash.get!(Orders.Order, id, authorize?: false).delivery_status == :not_required
    end
  end

  describe "cancelamento" do
    test "devolve o estoque e marca o pedido", %{conn: conn} do
      employee = user_fixture()
      product = product_fixture(stock_grams: 1_000)

      {:ok, order} =
        Orders.register_order(
          %{items: [sale_item(product, 400)]},
          actor: employee
        )

      conn =
        conn
        |> log_in(employee)
        |> post(~p"/pedidos/#{order.id}/cancelar", %{"reason" => "cliente desistiu"})

      assert redirected_to(conn) == ~p"/pedidos/#{order.id}"
      assert Ash.get!(Orders.Order, order.id, authorize?: false).status == :cancelled
      assert Decimal.equal?(Ash.get!(Product, product.id, authorize?: false).stock_grams, 1_000)
    end
  end
end
