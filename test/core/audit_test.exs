defmodule Core.AuditTest do
  use Core.DataCase, async: true

  require Ash.Query

  import Core.Fixtures

  alias Core.Audit
  alias Core.Audit.Entry
  alias Core.Inventory
  alias Core.Orders

  # O log é lido pelo admin; os testes de conteúdo usam este atalho para não
  # repetir o ator em toda leitura.
  defp log(actor) do
    Entry
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(actor: actor)
  end

  defp actions(actor), do: actor |> log() |> Enum.map(& &1.action)

  defp ultima(actor), do: actor |> log() |> List.last()

  describe "estoque" do
    test "cada movimentação grava quem fez e o que fez" do
      admin = admin_fixture(name: "Chefe")
      product = product_fixture(name: "Café", stock_grams: 500, cost_per_gram: "0.02")

      {:ok, product} =
        Inventory.add_stock(
          product,
          Decimal.new(250),
          Decimal.new("0.03"),
          %{label: "Caixa da feira", reason: "Compra"},
          actor: admin
        )

      entrada = ultima(admin)
      assert entrada.action == :stock_in
      assert entrada.user_name == "Chefe"
      assert entrada.subject_type == :product
      assert entrada.subject_label == "Café"
      assert entrada.summary =~ "Entrada de 250g"
      assert entrada.summary =~ "Caixa da feira"
      assert entrada.details["grams"] == "250"

      {:ok, product} =
        Inventory.remove_stock(
          product,
          Decimal.new(100),
          batch_of(product).id,
          %{reason: "Perda"},
          actor: admin
        )

      saida = ultima(admin)
      assert saida.action == :stock_out
      assert saida.summary =~ "Saída de 100g"
      assert saida.summary =~ "Perda"

      {:ok, _product} =
        Inventory.adjust_stock(product, Decimal.new(300), batch_of(product).id, %{}, actor: admin)

      assert ultima(admin).action == :stock_adjusted
    end

    test "o saldo inicial do cadastro também entra no log" do
      admin = admin_fixture()
      product_fixture(name: "Açafrão", stock_grams: 480, cost_per_gram: "0.52")

      assert [:product_created, :stock_in] = actions(admin)

      entrada = ultima(admin)
      assert entrada.summary =~ "Saldo inicial de 480g"
      assert entrada.subject_label == "Açafrão"
    end

    test "quem fez fica congelado: desativar a pessoa não apaga o rastro" do
      admin = admin_fixture(name: "Chefe")
      operador = user_fixture(name: "Joana", can_manage_stock: true)
      product = product_fixture()

      {:ok, _} =
        Inventory.add_stock(product, Decimal.new(100), Decimal.new("0.03"), %{}, actor: operador)

      # Joana sai da loja. O que ela fez continua dizendo o nome dela — é o
      # caso em que o log mais importa.
      {:ok, _desativada} = Core.Accounts.User.set_active(operador, false, authorize?: false)

      entrada = ultima(admin)
      assert entrada.user_name == "Joana"
      assert entrada.user_id == operador.id
    end
  end

  describe "produtos" do
    test "alteração de preço vira linha, e salvar sem mudar nada não" do
      admin = admin_fixture()
      product = product_fixture(name: "Café", price_per_gram: "0.05")

      {:ok, product} =
        Inventory.update_product(product, %{price_per_gram: Decimal.new("0.06")}, actor: admin)

      alteracao = ultima(admin)
      assert alteracao.action == :product_updated
      assert alteracao.summary == "Preço alterado de R$ 50,00/kg para R$ 60,00/kg"
      assert alteracao.details["price_per_gram"] == %{"de" => "0.05", "para" => "0.06"}

      antes = length(log(admin))

      # Mesmo valor escrito de outro jeito: continua sendo o mesmo preço.
      {:ok, product} =
        Inventory.update_product(product, %{price_per_gram: Decimal.new("0.0600")}, actor: admin)

      assert length(log(admin)) == antes

      {:ok, _product} = Inventory.update_product(product, %{active: false}, actor: admin)
      assert ultima(admin).summary == "Produto desativado"
    end
  end

  describe "pedidos" do
    test "a venda e o cancelamento dizem quem foi" do
      admin = admin_fixture(name: "Chefe")
      vendedor = user_fixture(name: "Joana", can_manage_orders: true)
      product = product_fixture(price_per_gram: "0.10", stock_grams: 1_000)

      {:ok, order} =
        Orders.register_order(
          %{customer_name: "Dona Marta", items: [sale_item(product, 100)]},
          actor: vendedor
        )

      venda = ultima(admin)
      assert venda.action == :order_registered
      assert venda.user_name == "Joana"
      assert venda.subject_type == :order
      assert venda.subject_label == Orders.code(order)
      assert venda.summary =~ "Venda de R$ 10,00 em 1 item"
      assert venda.summary =~ "Dona Marta"

      {:ok, _order} = Orders.cancel_order(order, %{reason: "cliente desistiu"}, actor: admin)

      # O cancelamento devolve estoque: as duas coisas ficam registradas, e a
      # devolução é do mesmo ator.
      assert [:stock_return, :order_cancelled] =
               admin |> actions() |> Enum.take(-2)

      cancelamento = ultima(admin)
      assert cancelamento.user_name == "Chefe"
      assert cancelamento.summary =~ "Pedido cancelado e estoque devolvido"
      assert cancelamento.summary =~ "cliente desistiu"
    end

    test "despacho e entrega registram o entregador e quem marcou" do
      admin = admin_fixture(name: "Chefe")
      driver = driver_fixture(name: "Bruno")
      product = product_fixture(stock_grams: 1_000)

      {:ok, order} =
        Orders.register_order(
          %{
            items: [sale_item(product, 100)],
            delivery_status: :pending,
            delivery_address: "Rua A, 10"
          },
          actor: admin
        )

      {:ok, order} = Orders.assign_driver(order, driver.id, actor: admin)
      despacho = ultima(admin)
      assert despacho.action == :order_driver_assigned
      assert despacho.summary =~ "despachada para Bruno"
      assert despacho.user_name == "Chefe"

      {:ok, order} = Orders.mark_delivered(order, actor: driver)
      entrega = ultima(admin)
      assert entrega.action == :order_delivered
      assert entrega.user_name == "Bruno"

      {:ok, _order} = Orders.reopen_delivery(order, actor: admin)
      assert ultima(admin).action == :order_reopened
    end
  end

  describe "quem pode ler" do
    setup do
      admin = admin_fixture()
      product_fixture()
      %{admin: admin}
    end

    test "só o admin", %{admin: admin} do
      assert [_ | _] = Ash.read!(Entry, actor: admin)

      # Nem o funcionário mais autorizado do balcão entra: o log existe para
      # conferir o trabalho dele.
      # Quem não é admin não recebe erro, recebe lista vazia: a policy vira
      # filtro (`no_filter_static_forbidden_reads?: false`). O efeito é o
      # mesmo — não existe log para quem não pode lê-lo.
      gerente = user_fixture(can_manage_stock: true, can_manage_orders: true)
      assert {:ok, []} = Ash.read(Entry, actor: gerente)

      assert {:ok, []} = Ash.read(Entry, actor: driver_fixture())
      assert {:ok, []} = Ash.read(Entry, actor: nil)
    end

    test "o log não é reescrito por ninguém", %{admin: admin} do
      entry = admin |> log() |> hd()

      # Sem ação de update nem de destroy no recurso: não é questão de
      # permissão, é que o caminho não existe — o Ash nem monta o changeset.
      assert_raise ArgumentError, ~r/No such update action/, fn ->
        entry
        |> Ash.Changeset.for_update(:update, %{summary: "outra coisa"}, authorize?: false)
        |> Ash.update!()
      end

      assert_raise Ash.Error.Invalid, ~r/No primary action of type :destroy/, fn ->
        Ash.destroy!(entry, authorize?: false)
      end

      # E escrever à mão, mesmo como admin, é barrado pela policy.
      assert {:error, _} =
               Entry
               |> Ash.Changeset.for_create(
                 :record,
                 %{
                   action: :stock_in,
                   subject_type: :product,
                   subject_id: Ash.UUID.generate(),
                   subject_label: "Inventado",
                   summary: "linha forjada"
                 },
                 actor: admin
               )
               |> Ash.create()
    end
  end

  describe "formatação" do
    test "peso e dinheiro saem como a loja fala" do
      assert Audit.grams(Decimal.new("250")) == "250g"
      assert Audit.grams(Decimal.new("-120")) == "120g"
      assert Audit.grams(Decimal.new("500.00")) == "500g"
      assert Audit.grams(Decimal.new("1000")) == "1kg"
      assert Audit.grams(Decimal.new("2400")) == "2.4kg"

      assert Audit.money(Decimal.new("8.5")) == "R$ 8,50"
      assert Audit.money(Decimal.new("102")) == "R$ 102,00"
    end
  end
end
