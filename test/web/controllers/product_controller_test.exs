defmodule Web.ProductControllerTest do
  use Web.ConnCase, async: true

  import Inertia.Testing
  import Core.Fixtures

  alias Core.Inventory.Product

  describe "quem pode o quê" do
    test "funcionário comum lê o catálogo", %{conn: conn} do
      product = product_fixture(name: "Café")
      conn = conn |> log_in(user_fixture()) |> get(~p"/produtos")

      assert inertia_component(conn) == "Products/Index"
      assert %{products: [%{name: "Café"}]} = inertia_props(conn)
      assert product.name == "Café"
    end

    test "funcionário comum não abre o cadastro", %{conn: conn} do
      conn = conn |> log_in(user_fixture()) |> get(~p"/produtos/novo")

      assert redirected_to(conn) == ~p"/produtos"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "permissão"
    end

    test "funcionário autorizado abre o cadastro", %{conn: conn} do
      conn = conn |> log_in(user_fixture(can_manage_stock: true)) |> get(~p"/produtos/novo")

      assert inertia_component(conn) == "Products/Form"
    end
  end

  describe "cadastro" do
    setup %{conn: conn} do
      %{conn: log_in(conn, admin_fixture())}
    end

    test "converte preço por kg em preço por grama e aceita vírgula", %{conn: conn} do
      conn =
        post(conn, ~p"/produtos", %{
          "name" => "Amêndoa",
          "unit" => "kg",
          "price" => "78,50",
          "min_stock" => "1",
          "initial_stock" => "3,5"
        })

      assert %{id: id} = redirected_params(conn)
      product = Ash.get!(Product, id, authorize?: false)

      assert Decimal.equal?(product.price_per_gram, "0.0785")
      assert Decimal.equal?(product.min_stock_grams, 1_000)
      assert Decimal.equal?(product.stock_grams, 3_500)
    end

    test "número inválido volta com erro no campo", %{conn: conn} do
      conn =
        post(conn, ~p"/produtos", %{
          "name" => "Quebrado",
          "unit" => "kg",
          "price" => "muito caro"
        })

      assert redirected_to(conn) == ~p"/produtos/novo"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "número válido"
    end
  end

  describe "movimentação de estoque" do
    setup %{conn: conn} do
      %{conn: log_in(conn, admin_fixture()), product: product_fixture(stock_grams: 1_000)}
    end

    test "entrada em kg soma os gramas certos e abre o lote pelo custo por kg",
         %{conn: conn, product: product} do
      conn =
        post(conn, ~p"/produtos/#{product.id}/estoque", %{
          "kind" => "in",
          "quantity" => "2,5",
          "unit" => "kg",
          "cost" => "40",
          "batch_label" => "Caixa da feira",
          "reason" => "Compra"
        })

      assert redirected_to(conn) == ~p"/produtos/#{product.id}"
      assert Decimal.equal?(Ash.get!(Product, product.id, authorize?: false).stock_grams, 3_500)

      # R$ 40 por kg digitados na tela viram R$ 0,04 por grama no domínio.
      batch = product |> batches() |> List.last()
      assert batch.label == "Caixa da feira"
      assert Decimal.equal?(batch.remaining_grams, 2_500)
      assert Decimal.equal?(batch.cost_per_gram, Decimal.new("0.04"))
    end

    test "entrada sem custo é recusada", %{conn: conn, product: product} do
      conn =
        post(conn, ~p"/produtos/#{product.id}/estoque", %{
          "kind" => "in",
          "quantity" => "1",
          "unit" => "kg"
        })

      assert redirected_to(conn) == ~p"/produtos/#{product.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "custou"
      assert Decimal.equal?(Ash.get!(Product, product.id, authorize?: false).stock_grams, 1_000)
    end

    test "saída sem lote é recusada", %{conn: conn, product: product} do
      conn =
        post(conn, ~p"/produtos/#{product.id}/estoque", %{
          "kind" => "out",
          "quantity" => "100",
          "unit" => "g"
        })

      assert redirected_to(conn) == ~p"/produtos/#{product.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "lote"
      assert Decimal.equal?(Ash.get!(Product, product.id, authorize?: false).stock_grams, 1_000)
    end

    test "saída além do saldo do lote é recusada", %{conn: conn, product: product} do
      conn =
        post(conn, ~p"/produtos/#{product.id}/estoque", %{
          "kind" => "out",
          "quantity" => "5",
          "unit" => "kg",
          "batch_id" => batch_of(product).id
        })

      assert redirected_to(conn) == ~p"/produtos/#{product.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "insuficiente"
      assert Decimal.equal?(Ash.get!(Product, product.id, authorize?: false).stock_grams, 1_000)
    end
  end

  describe "custo na tela" do
    test "quem gerencia estoque recebe custo do lote e valor em estoque", %{conn: conn} do
      product = product_fixture(stock_grams: 1_000, cost_per_gram: "0.02")
      conn = conn |> log_in(admin_fixture()) |> get(~p"/produtos/#{product.id}")

      assert %{product: product_prop, batches: [batch]} = inertia_props(conn)
      assert product_prop.stockCostValue == 20.0
      assert batch.costPerGram == 0.02
      assert batch.costPerKg == 20.0
    end

    test "funcionário comum vê o lote mas não o custo", %{conn: conn} do
      product = product_fixture(stock_grams: 1_000, cost_per_gram: "0.02")
      conn = conn |> log_in(user_fixture()) |> get(~p"/produtos/#{product.id}")

      assert %{product: product_prop, batches: [batch], movements: []} = inertia_props(conn)
      refute Map.has_key?(product_prop, :stockCostValue)
      refute Map.has_key?(batch, :costPerGram)
      assert batch.remainingGrams == 1_000.0
    end
  end

  test "a tela do produto traz o histórico para quem gerencia estoque", %{conn: conn} do
    product = product_fixture(stock_grams: 500)
    conn = conn |> log_in(admin_fixture()) |> get(~p"/produtos/#{product.id}")

    assert inertia_component(conn) == "Products/Show"
    assert %{movements: [%{kind: :in}], movementsPage: page} = inertia_props(conn)
    assert page == %{number: 1, size: 20, count: 1, pages: 1}
  end

  describe "histórico e o pedido" do
    test "a saída da venda aponta para o pedido que a gerou", %{conn: conn} do
      admin = admin_fixture()
      product = product_fixture(stock_grams: 1_000)

      {:ok, order} =
        Core.Orders.register_order(%{items: [sale_item(product, 200)]}, actor: admin)

      conn = conn |> log_in(admin) |> get(~p"/produtos/#{product.id}")

      assert %{movements: movements, canOpenOrders: true} = inertia_props(conn)
      assert saida = Enum.find(movements, &(&1.kind == :out))
      assert saida.orderId == order.id
      assert saida.orderCode == Core.Orders.code(order)

      # A entrada do lote não veio de venda nenhuma.
      assert entrada = Enum.find(movements, &(&1.kind == :in))
      refute entrada.orderId
    end

    test "sem permissão de pedidos o histórico não vira link", %{conn: conn} do
      employee = user_fixture(can_manage_stock: true)
      product = product_fixture(stock_grams: 1_000)

      {:ok, _} =
        Core.Orders.register_order(%{items: [sale_item(product, 200)]}, actor: employee)

      conn = conn |> log_in(employee) |> get(~p"/produtos/#{product.id}")

      assert %{canOpenOrders: false, movements: movements} = inertia_props(conn)
      # O código continua na tela: ele identifica a venda mesmo sem link.
      assert Enum.any?(movements, & &1.orderCode)
    end
  end

  describe "histórico paginado" do
    setup %{conn: conn} do
      admin = admin_fixture()
      product = product_fixture(stock_grams: 100)

      # 24 movimentações com o lote inicial: 25 linhas no total.
      for _ <- 1..24 do
        {:ok, _} =
          Core.Inventory.add_stock(
            product,
            Decimal.new(100),
            Decimal.new("0.02"),
            %{},
            authorize?: false
          )
      end

      %{conn: log_in(conn, admin), product: product}
    end

    test "a primeira página traz 20 e conta o resto", %{conn: conn, product: product} do
      conn = get(conn, ~p"/produtos/#{product.id}")

      assert %{movements: movements, movementsPage: page} = inertia_props(conn)
      assert length(movements) == 20
      assert page == %{number: 1, size: 20, count: 25, pages: 2}
    end

    test "a segunda página traz o que sobrou, sem repetir", %{conn: conn, product: product} do
      primeira = inertia_props(get(conn, ~p"/produtos/#{product.id}"))
      segunda = inertia_props(get(conn, ~p"/produtos/#{product.id}?historico=2"))

      assert length(segunda.movements) == 5
      assert segunda.movementsPage.number == 2

      ids = fn props -> Enum.map(props.movements, & &1.id) end
      assert ids.(primeira) -- ids.(segunda) == ids.(primeira)
    end

    test "página inválida cai na primeira", %{conn: conn, product: product} do
      conn = get(conn, ~p"/produtos/#{product.id}?historico=-3")

      assert %{movementsPage: %{number: 1}} = inertia_props(conn)
    end

    test "sem permissão de estoque não há histórico nem contagem", %{product: product} do
      conn =
        Phoenix.ConnTest.build_conn()
        |> log_in(user_fixture())
        |> get(~p"/produtos/#{product.id}")

      assert %{movements: [], movementsPage: %{count: 0}} = inertia_props(conn)
    end
  end
end
