defmodule Core.InventoryTest do
  use Core.DataCase, async: true

  import Core.Fixtures

  alias Core.Inventory
  alias Core.Inventory.Product

  describe "movimentação de estoque" do
    test "entrada abre um lote com o custo pago e grava o histórico" do
      admin = admin_fixture()
      product = product_fixture(stock_grams: 500, cost_per_gram: "0.02")

      {:ok, product} =
        Inventory.add_stock(
          product,
          Decimal.new(250),
          Decimal.new("0.03"),
          %{label: "Caixa da feira", reason: "Compra"},
          actor: admin
        )

      assert Decimal.equal?(product.stock_grams, 750)

      assert [inicial, novo] = batches(product)
      assert novo.label == "Caixa da feira"
      assert Decimal.equal?(novo.cost_per_gram, Decimal.new("0.03"))
      assert Decimal.equal?(novo.remaining_grams, 250)
      assert Decimal.equal?(novo.initial_grams, 250)
      assert novo.user_id == admin.id

      # O lote antigo não é tocado: custos diferentes não se misturam.
      assert Decimal.equal?(inicial.cost_per_gram, Decimal.new("0.02"))
      assert Decimal.equal?(inicial.remaining_grams, 500)

      assert [movement, _saldo_inicial] =
               Inventory.list_movements_for_product!(product.id, actor: admin)

      assert movement.kind == :in
      assert movement.batch_id == novo.id
      assert Decimal.equal?(movement.grams, 250)
      assert Decimal.equal?(movement.balance_after, 750)
      assert Decimal.equal?(movement.batch_balance_after, 250)
      assert Decimal.equal?(movement.total_cost, Decimal.new("7.50"))
      assert movement.reason == "Compra"
      assert movement.user_id == admin.id
    end

    test "entrada sem nome de lote ganha um pelo dia" do
      admin = admin_fixture()
      product = product_fixture()

      {:ok, product} =
        Inventory.add_stock(product, Decimal.new(100), Decimal.new("0.01"), %{}, actor: admin)

      hoje = Core.Clock.today()
      esperado = "Lote de #{pad(hoje.day)}/#{pad(hoje.month)}"

      assert product |> batches() |> List.last() |> Map.get(:label) == esperado
    end

    test "saída sai do lote informado e grava gramas negativas" do
      admin = admin_fixture()
      product = product_fixture(stock_grams: 500)
      caro = batch_fixture(product, grams: 300, cost_per_gram: "0.09", label: "Caro")

      {:ok, product} =
        Inventory.remove_stock(product, Decimal.new(120), caro.id, %{}, actor: admin)

      assert Decimal.equal?(product.stock_grams, 680)

      [barato, caro] = batches(product)
      assert Decimal.equal?(barato.remaining_grams, 500)
      assert Decimal.equal?(caro.remaining_grams, 180)

      [movement | _] = Inventory.list_movements_for_product!(product.id, actor: admin)
      assert movement.kind == :out
      assert movement.batch_id == caro.id
      assert Decimal.equal?(movement.grams, -120)
      assert Decimal.equal?(movement.cost_per_gram, Decimal.new("0.09"))
      assert Decimal.equal?(movement.total_cost, Decimal.new("-10.80"))
    end

    test "saída maior que o lote é recusada mesmo com saldo no produto" do
      admin = admin_fixture()
      product = product_fixture(stock_grams: 1_000)
      pequeno = batch_fixture(product, grams: 50)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Inventory.remove_stock(product, Decimal.new(51), pequeno.id, %{}, actor: admin)

      assert Exception.message(error) =~ "estoque insuficiente no lote"

      assert Decimal.equal?(Ash.get!(Product, product.id, authorize?: false).stock_grams, 1_050)
    end

    test "saída de lote de outro produto é recusada" do
      admin = admin_fixture()
      product = product_fixture()
      outro = product_fixture()

      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.remove_stock(product, Decimal.new(10), batch_of(outro).id, %{},
                 actor: admin
               )
    end

    test "lote esgotado sai das opções de venda mas fica no histórico" do
      admin = admin_fixture()
      product = product_fixture(stock_grams: 200)
      batch = batch_of(product)

      {:ok, product} =
        Inventory.remove_stock(product, Decimal.new(200), batch.id, %{}, actor: admin)

      assert Decimal.equal?(product.stock_grams, 0)

      [batch] = batches(product)
      assert Decimal.equal?(batch.remaining_grams, 0)
      assert batch.depleted_at

      assert [] = Inventory.list_available_batches!(actor: admin)
    end

    test "devolução volta para o mesmo lote, sem abrir outro" do
      admin = admin_fixture()
      product = product_fixture(stock_grams: 500, cost_per_gram: "0.04")
      batch = batch_of(product)

      {:ok, product} =
        Inventory.remove_stock(product, Decimal.new(500), batch.id, %{}, actor: admin)

      {:ok, product} =
        Inventory.return_stock(product, Decimal.new(200), batch.id, %{}, actor: admin)

      assert Decimal.equal?(product.stock_grams, 200)

      assert [batch] = batches(product)
      assert Decimal.equal?(batch.remaining_grams, 200)
      assert Decimal.equal?(batch.cost_per_gram, Decimal.new("0.04"))
      refute batch.depleted_at
    end

    test "ajuste define o saldo do lote e registra a diferença" do
      admin = admin_fixture()
      product = product_fixture(stock_grams: 900)
      batch = batch_of(product)

      {:ok, product} =
        Inventory.adjust_stock(product, Decimal.new(870), batch.id, %{reason: "Contagem"},
          actor: admin
        )

      assert Decimal.equal?(product.stock_grams, 870)

      [movement | _] = Inventory.list_movements_for_product!(product.id, actor: admin)
      assert movement.kind == :adjustment
      assert Decimal.equal?(movement.grams, -30)
      assert Decimal.equal?(movement.batch_balance_after, 870)
    end

    test "saldo inicial do cadastro vira o primeiro lote e a primeira movimentação" do
      admin = admin_fixture()

      product =
        product_fixture(
          stock_grams: 2_000,
          cost_per_gram: "0.015",
          batch_label: "Compra de estreia"
        )

      assert [batch] = batches(product)
      assert batch.label == "Compra de estreia"
      assert Decimal.equal?(batch.remaining_grams, 2_000)
      assert Decimal.equal?(batch.cost_per_gram, Decimal.new("0.015"))

      assert [movement] = Inventory.list_movements_for_product!(product.id, actor: admin)
      assert movement.kind == :in
      assert movement.batch_id == batch.id
      assert Decimal.equal?(movement.grams, 2_000)
      assert Decimal.equal?(movement.total_cost, Decimal.new("30.00"))
      assert movement.reason == "Saldo inicial"
    end

    test "produto sem saldo inicial não abre lote nenhum" do
      product = product_fixture(stock_grams: 0)

      assert [] = batches(product)
      assert Decimal.equal?(product.stock_grams, 0)
    end
  end

  describe "valor em estoque" do
    test "soma o que sobrou de cada lote pelo custo dele" do
      admin = admin_fixture()
      product = product_fixture(stock_grams: 1_000, cost_per_gram: "0.02")
      caro = batch_fixture(product, grams: 500, cost_per_gram: "0.05")

      # 1000g × 0,02 + 500g × 0,05 = 20 + 25
      product = Ash.load!(product, :stock_cost_value, actor: admin)
      assert Decimal.equal?(product.stock_cost_value, Decimal.new("45.00"))

      {:ok, product} =
        Inventory.remove_stock(product, Decimal.new(500), caro.id, %{}, actor: admin)

      product = Ash.load!(product, :stock_cost_value, actor: admin)
      assert Decimal.equal?(product.stock_cost_value, Decimal.new("20.00"))
    end
  end

  describe "permissões" do
    test "funcionário comum não cadastra nem movimenta" do
      employee = user_fixture()
      product = product_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Inventory.create_product(
                 %{name: "Novo", unit: :kg, price_per_gram: Decimal.new("0.1")},
                 actor: employee
               )

      assert {:error, %Ash.Error.Forbidden{}} =
               Inventory.add_stock(product, Decimal.new(10), Decimal.new("0.01"), %{},
                 actor: employee
               )
    end

    test "funcionário com can_manage_stock movimenta" do
      employee = user_fixture(can_manage_stock: true)
      product = product_fixture(stock_grams: 100)

      assert {:ok, product} =
               Inventory.add_stock(product, Decimal.new(10), Decimal.new("0.01"), %{},
                 actor: employee
               )

      assert Decimal.equal?(product.stock_grams, 110)
    end

    test "funcionário comum lê o catálogo e os lotes, mas não o histórico" do
      employee = user_fixture()
      admin = admin_fixture()
      product = product_fixture()

      assert [_ | _] = Inventory.list_products!(actor: employee)

      # O lote ele precisa enxergar para escolher de qual vende; o custo é que
      # não sai daqui para a tela dele (ver `Web.Serializers`).
      assert [_ | _] = Inventory.list_batches_for_product!(product.id, actor: employee)

      # Leitura sem permissão volta vazia em vez de erro: as policies de read
      # do Ash viram filtro (`no_filter_static_forbidden_reads?: false`). O
      # efeito prático é o mesmo — o histórico não vaza.
      assert [] = Inventory.list_movements_for_product!(product.id, actor: employee)
      assert [_ | _] = Inventory.list_movements_for_product!(product.id, actor: admin)
    end

    test "lote não é criado nem alterado por fora das ações de estoque" do
      admin = admin_fixture()
      product = product_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Core.Inventory.Batch
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   product_id: product.id,
                   label: "Na marra",
                   cost_per_gram: Decimal.new(0),
                   initial_grams: Decimal.new(1),
                   remaining_grams: Decimal.new(1)
                 },
                 actor: admin
               )
               |> Ash.create()
    end
  end

  test "low_stock? acompanha o mínimo configurado" do
    admin = admin_fixture()
    product = product_fixture(stock_grams: 1_000, min_stock_grams: 900)

    product = Ash.load!(product, :low_stock?, actor: admin)
    refute product.low_stock?

    {:ok, product} =
      Inventory.remove_stock(product, Decimal.new(150), batch_of(product).id, %{}, actor: admin)

    product = Ash.load!(product, :low_stock?, actor: admin)
    assert product.low_stock?
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
