defmodule Web.DashboardControllerTest do
  use Web.ConnCase, async: true

  import Inertia.Testing
  import Ecto.Query
  import Core.Fixtures

  alias Core.Accounts.Permissions
  alias Core.Clock
  alias Core.Orders

  defp sale_com_entrega(actor, product, opts) do
    {:ok, order} =
      Orders.register_order(
        %{
          items: [sale_item(product, 100)],
          customer_name: Keyword.get(opts, :customer, "Dona Rita"),
          delivery_status: :pending,
          delivery_address: Keyword.get(opts, :address, "Rua das Flores, 100"),
          delivery_lat: Decimal.new(Keyword.get(opts, :lat, "-23.55")),
          delivery_lon: Decimal.new(Keyword.get(opts, :lon, "-46.63"))
        },
        actor: actor
      )

    order
  end

  defp sale(actor, product, grams \\ 100) do
    {:ok, order} =
      Orders.register_order(
        %{items: [sale_item(product, grams)]},
        actor: actor
      )

    order
  end

  describe "resumo" do
    setup %{conn: conn} do
      admin = admin_fixture()
      product = product_fixture(price_per_gram: "0.10", stock_grams: 10_000)

      %{conn: log_in(conn, admin), admin: admin, product: product}
    end

    test "o padrão é hoje", %{conn: conn} do
      today = Date.to_iso8601(Clock.today())
      conn = get(conn, ~p"/")

      assert inertia_component(conn) == "Dashboard"
      assert %{range: %{from: ^today, to: ^today}, today: ^today} = inertia_props(conn)
    end

    test "conta os pedidos e o faturamento de hoje", %{conn: conn, admin: admin, product: product} do
      sale(admin, product, 100)
      sale(admin, product, 200)

      props = inertia_props(get_partial(conn, ~p"/", "Dashboard", ["sales"]))

      assert props.sales.totals.orders == 2
      assert props.sales.totals.revenue == 30.0
    end

    test "o lucro desconta o custo do lote vendido", %{conn: conn, admin: admin} do
      # Vende a 0,10 o que custou 0,04: sobram 0,06 por grama.
      product =
        product_fixture(price_per_gram: "0.10", stock_grams: 10_000, cost_per_gram: "0.04")

      sale(admin, product, 500)

      props = inertia_props(get_partial(conn, ~p"/", "Dashboard", ["sales"]))

      assert props.sales.totals.revenue == 50.0
      assert props.sales.totals.profit == 30.0
    end

    test "o período pedido manda nos números do período, e hoje segue hoje", %{
      conn: conn,
      admin: admin,
      product: product
    } do
      sale(admin, product, 100)

      # Um intervalo no passado não pode conter a venda de hoje.
      partial =
        get_partial(conn, ~p"/?de=2020-01-01&ate=2020-01-31", "Dashboard", ["sales", "recent"])

      assert %{sales: sales, recent: []} = inertia_props(partial)
      assert sales.totals.orders == 0
      assert sales.totals.revenue == +0.0

      # ...mas a fila de agora, dentro da categoria de entrega, não é do
      # período: a venda de hoje continua lá.
      entrega =
        get_partial(conn, ~p"/?de=2020-01-01&ate=2020-01-31", "Dashboard", ["delivery"])

      assert inertia_props(entrega).delivery.now.toDeliver == 1
    end

    test "o carregamento inicial não traz as categorias pesadas", %{conn: conn} do
      props = inertia_props(get(conn, ~p"/"))

      # A home é só análise: a primeira resposta leva o recorte de datas e
      # nada mais — cada bloco busca o próprio dado depois.
      assert Map.has_key?(props, :range)
      assert Map.has_key?(props, :costs)
      # A lista de seções vai no carregamento inicial: é ela que diz à tela
      # quais blocos existem para buscar.
      assert Map.has_key?(props, :sections)

      for categoria <- [:map, :sales, :hours, :products, :team, :delivery, :stock, :recent] do
        refute Map.has_key?(props, categoria)
      end
    end

    test "o mapa leva só os pedidos que têm coordenada", %{
      conn: conn,
      admin: admin,
      product: product
    } do
      entrega = sale_com_entrega(admin, product, [])
      # Retirada no balcão: não tem endereço, então não tem ponto.
      sale(admin, product, 100)

      props = inertia_props(get_partial(conn, ~p"/", "Dashboard", ["map"]))

      assert [ponto] = props.map
      assert ponto.id == entrega.id
      assert ponto.customerName == "Dona Rita"
      assert ponto.deliveryAddress == "Rua das Flores, 100"
      assert ponto.deliveryLat == -23.55
      assert ponto.deliveryLon == -46.63
      # O balão mostra o estado da entrega e o valor; os dois vêm daqui.
      assert ponto.deliveryStatus == :pending
      assert ponto.total > 0
    end

    test "cada categoria é buscada sozinha", %{conn: conn, admin: admin, product: product} do
      sale(admin, product, 100)

      props = inertia_props(get_partial(conn, ~p"/", "Dashboard", ["hours"]))

      assert length(props.hours) == 24
      # Pedir horários não pode arrastar o resto junto — é isso que deixa a
      # página leve.
      refute Map.has_key?(props, :products)
      refute Map.has_key?(props, :sales)
    end

    test "datas invertidas são corrigidas em vez de dar erro", %{conn: conn} do
      conn = get(conn, ~p"/?de=2026-08-20&ate=2026-08-10")

      assert %{range: %{from: "2026-08-10", to: "2026-08-20"}} = inertia_props(conn)
    end

    test "data ilegível cai no padrão", %{conn: conn} do
      today = Date.to_iso8601(Clock.today())
      conn = get(conn, ~p"/?de=ontem&ate=amanha")

      assert %{range: %{from: ^today, to: ^today}} = inertia_props(conn)
    end

    test "fila de entrega e entregues hoje", %{conn: conn, admin: admin, product: product} do
      aguardando = sale(admin, product)
      entregue = sale(admin, product)
      {:ok, _} = Orders.mark_delivered(entregue, actor: admin)

      props = inertia_props(get_partial(conn, ~p"/", "Dashboard", ["delivery"]))

      assert props.delivery.now.toDeliver == 1
      assert props.delivery.now.deliveredToday == 1
      assert aguardando.delivery_status == :pending
    end
  end

  test "funcionário vê os próprios números", %{conn: conn} do
    admin = admin_fixture()
    employee = user_fixture(can_view_dashboard: true, dashboard_sections: :all)
    product = product_fixture(price_per_gram: "0.10", stock_grams: 10_000)

    sale(admin, product, 100)
    sale(employee, product, 100)

    conn = log_in(conn, employee)

    props = inertia_props(get_partial(conn, ~p"/", "Dashboard", ["sales", "delivery"]))

    assert props.sales.totals.orders == 1
    assert props.delivery.now.toDeliver == 1

    # Funcionário sem permissão de estoque não recebe lucro nenhum: o campo
    # simplesmente não sai do servidor.
    refute Map.has_key?(props.sales.totals, :profit)
  end

  describe "análise por categoria" do
    test "as séries do período respeitam quem está olhando", %{conn: conn} do
      admin = admin_fixture()
      employee = user_fixture(can_view_dashboard: true, dashboard_sections: :all)
      driver = driver_fixture()

      product =
        product_fixture(price_per_gram: "0.10", stock_grams: 10_000, cost_per_gram: "0.04")

      meu = sale(employee, product, 100)
      _alheio = sale(admin, product, 300)
      {:ok, _} = Orders.assign_driver(meu, driver.id, actor: employee)

      hoje = Date.to_iso8601(Clock.today())
      categorias = ["sales", "hours", "products", "team", "delivery", "stock"]

      # O admin enxerga a loja inteira, com lucro.
      props = inertia_props(get_partial(log_in(conn, admin), ~p"/", "Dashboard", categorias))

      assert [%{date: ^hoje, orders: 2, revenue: 40.0, profit: 24.0}] = props.sales.daily
      assert props.sales.totals.ticket == 20.0
      assert [%{name: _, revenue: 40.0}] = props.products
      assert length(props.team) == 2
      assert props.delivery.summary.pending == 2
      assert props.delivery.summary.unassigned == 1
      assert [%{name: _, assigned: 1, delivered: 0}] = props.delivery.drivers
      assert props.stock.value > 0
      assert length(props.hours) == 24

      # O funcionário vê só o que registrou, e sem custo nenhum.
      seus = inertia_props(get_partial(log_in(conn, employee), ~p"/", "Dashboard", categorias))

      assert [%{orders: 1, revenue: 10.0}] = seus.sales.daily
      refute Map.has_key?(hd(seus.sales.daily), :profit)
      refute Map.has_key?(seus.stock, :value)
      assert [%{orders: 1}] = seus.team
    end

    test "período sem venda devolve a série zerada, não vazia", %{conn: conn} do
      admin = admin_fixture()
      ontem = Clock.today() |> Date.add(-1) |> Date.to_iso8601()

      props =
        inertia_props(
          get_partial(log_in(conn, admin), ~p"/?de=#{ontem}&ate=#{ontem}", "Dashboard", ["sales"])
        )

      assert [%{date: ^ontem, orders: 0, revenue: +0.0}] = props.sales.daily
      assert props.sales.totals.ticket == +0.0
    end

    test "a prazo: o que está em aberto agora e o que entrou no período", %{conn: conn} do
      admin = admin_fixture()
      employee = user_fixture(can_view_dashboard: true, dashboard_sections: [:receivables])
      product = product_fixture(price_per_gram: "0.10", stock_grams: 10_000)
      today = Clock.today()

      a_prazo = fn actor, grams, due ->
        {:ok, order} =
          Orders.register_order(
            %{items: [sale_item(product, grams)], customer_name: "Seu Zé", payment_due_on: due},
            actor: actor
          )

        order
      end

      _semana = a_prazo.(admin, 100, Date.add(today, 3))
      _longe = a_prazo.(admin, 200, Date.add(today, 40))
      pago = a_prazo.(admin, 300, Date.add(today, 10))
      {:ok, _} = Orders.mark_paid(pago, actor: admin)
      vencido = a_prazo.(admin, 400, today)
      _a_vista = sale(admin, product, 1_000)
      _do_funcionario = a_prazo.(employee, 500, Date.add(today, 3))

      # O domínio não aceita prazo no passado: o vencido é a venda de dias
      # atrás, e o atraso é escrito direto no banco.
      Core.Repo.update_all(
        from(o in "orders", where: o.id == type(^vencido.id, :binary_id)),
        set: [payment_due_on: Date.add(today, -4)]
      )

      props = inertia_props(get_partial(log_in(conn, admin), ~p"/", "Dashboard", ["receivables"]))
      r = props.receivables

      # Em aberto: 10 + 20 + 40 + 50 (o pago não entra).
      assert r.open == %{orders: 4, total: 120.0}
      assert r.overdue == %{orders: 1, total: 40.0}
      assert r.dueSoon == %{orders: 2, total: 60.0}

      assert [%{id: id, daysLate: 4, total: 40.0}] = r.overdueOrders
      assert id == vencido.id

      # No período (hoje): 150 a prazo de 250 vendidos, 30 recebidos em dia.
      assert r.period.orders == 5
      assert r.period.total == 150.0
      assert r.period.share == 150.0 / 250.0
      assert r.period.received == %{orders: 1, total: 30.0}
      assert r.period.receivedLate == 0

      assert Enum.sum(Enum.map(r.schedule, & &1.total)) == 120.0

      # O funcionário vê só o que ele mesmo vendeu a prazo.
      seus =
        inertia_props(get_partial(log_in(conn, employee), ~p"/", "Dashboard", ["receivables"]))

      assert seus.receivables.open == %{orders: 1, total: 50.0}
    end
  end

  describe "permissão do painel" do
    test "sem a permissão, a home é a dos pedidos", %{conn: conn} do
      conn = conn |> log_in(user_fixture()) |> get(~p"/")

      assert redirected_to(conn) == ~p"/pedidos"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "painel"
    end

    test "o admin recebe todas as seções", %{conn: conn} do
      props = inertia_props(get(log_in(conn, admin_fixture()), ~p"/"))

      assert props.sections == Permissions.dashboard_sections()
    end

    test "só as seções liberadas existem", %{conn: conn} do
      employee =
        user_fixture(can_view_dashboard: true, dashboard_sections: [:sales, :hours])

      conn = log_in(conn, employee)

      assert inertia_props(get(conn, ~p"/")).sections == [:sales, :hours]

      # Seção liberada responde...
      liberadas = inertia_props(get_partial(conn, ~p"/", "Dashboard", ["sales", "hours"]))

      assert liberadas.sales.totals.orders == 0
      assert length(liberadas.hours) == 24

      # ...e a que não foi liberada não é escondida na tela: ela não existe
      # como prop, nem quando a recarga parcial pede pelo nome.
      negadas =
        inertia_props(
          get_partial(conn, ~p"/", "Dashboard", [
            "team",
            "products",
            "delivery",
            "stock",
            "recent"
          ])
        )

      for section <- [:team, :products, :delivery, :stock, :recent] do
        refute Map.has_key?(negadas, section)
      end
    end

    test "painel liberado sem seção nenhuma abre vazio, e não com tudo", %{conn: conn} do
      conn = log_in(conn, user_fixture(can_view_dashboard: true))

      assert inertia_props(get(conn, ~p"/")).sections == []
      refute Map.has_key?(inertia_props(get_partial(conn, ~p"/", "Dashboard", ["sales"])), :sales)
    end

    test "as seções guardadas fora de ordem saem na ordem do painel", %{conn: conn} do
      employee =
        user_fixture(can_view_dashboard: true, dashboard_sections: [:recent, :hours, :sales])

      assert inertia_props(get(log_in(conn, employee), ~p"/")).sections == [
               :sales,
               :hours,
               :recent
             ]
    end
  end
end
