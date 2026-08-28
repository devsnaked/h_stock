defmodule Web.AuditControllerTest do
  use Web.ConnCase, async: true

  import Inertia.Testing
  import Core.Fixtures

  alias Core.Inventory
  alias Core.Orders

  describe "quem abre a tela" do
    test "funcionário comum é mandado de volta", %{conn: conn} do
      conn = conn |> log_in(user_fixture()) |> get(~p"/auditoria")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "administrador"
    end

    test "nem quem gerencia estoque e pedidos", %{conn: conn} do
      gerente = user_fixture(can_manage_stock: true, can_manage_orders: true)
      conn = conn |> log_in(gerente) |> get(~p"/auditoria")

      assert redirected_to(conn) == ~p"/"
    end

    test "entregador também não", %{conn: conn} do
      conn = conn |> log_in(driver_fixture()) |> get(~p"/auditoria")
      assert redirected_to(conn) in [~p"/", ~p"/entregas"]
    end

    test "deslogado vai para o login", %{conn: conn} do
      conn = get(conn, ~p"/auditoria")
      assert redirected_to(conn) == ~p"/sign-in"
    end
  end

  describe "admin" do
    setup %{conn: conn} do
      admin = admin_fixture(name: "Chefe")
      %{conn: log_in(conn, admin), admin: admin}
    end

    test "lista o que aconteceu, do mais novo para trás", %{conn: conn, admin: admin} do
      product = product_fixture(name: "Café", stock_grams: 500)

      {:ok, _product} =
        Inventory.add_stock(
          product,
          Decimal.new(250),
          Decimal.new("0.03"),
          %{label: "Caixa da feira"},
          actor: admin
        )

      conn = get(conn, ~p"/auditoria")

      assert inertia_component(conn) == "Audit/Index"
      assert %{entries: entries, page: page} = inertia_props(conn)

      assert [primeira | _] = entries
      assert primeira.action == :stock_in
      assert primeira.userName == "Chefe"
      assert primeira.summary =~ "Caixa da feira"
      assert page.count == length(entries)
    end

    test "filtra por tipo", %{conn: conn, admin: admin} do
      product = product_fixture(price_per_gram: "0.10", stock_grams: 1_000)
      {:ok, _} = Orders.register_order(%{items: [sale_item(product, 100)]}, actor: admin)

      conn = get(conn, ~p"/auditoria?tipo=pedidos")
      assert %{entries: entries, filter: "pedidos"} = inertia_props(conn)
      assert Enum.all?(entries, &(&1.subjectType == :order))
      assert :order_registered in Enum.map(entries, & &1.action)

      conn = get(conn, ~p"/auditoria?tipo=produtos")
      assert %{entries: entries} = inertia_props(conn)
      assert Enum.all?(entries, &(&1.action == :product_created))
    end

    test "filtra por quem fez", %{conn: conn} do
      operador = user_fixture(name: "Joana", can_manage_stock: true)
      product = product_fixture()

      {:ok, _} =
        Inventory.add_stock(product, Decimal.new(100), Decimal.new("0.03"), %{}, actor: operador)

      conn = get(conn, ~p"/auditoria?quem=#{operador.id}")
      assert %{entries: entries, authors: authors} = inertia_props(conn)

      assert Enum.all?(entries, &(&1.userName == "Joana"))
      # O seletor oferece quem já apareceu no log — Joana e quem criou o
      # produto (o fixture roda sem ator, então só ela).
      assert "Joana" in Enum.map(authors, & &1.name)

      refute Enum.empty?(entries)
    end

    test "busca pelo texto que a pessoa enxerga", %{conn: conn, admin: admin} do
      product = product_fixture(name: "Açafrão", price_per_gram: "0.10", stock_grams: 1_000)
      {:ok, order} = Orders.register_order(%{items: [sale_item(product, 100)]}, actor: admin)

      conn = get(conn, ~p"/auditoria?busca=Açafrão")
      assert %{entries: entries, search: "Açafrão"} = inertia_props(conn)
      assert Enum.all?(entries, &(&1.subjectLabel == "Açafrão"))

      # O código do pedido é o que o administrador tem na mão quando alguém
      # reclama de uma venda — e ele traz o pedido **e** a baixa de estoque
      # que a venda causou, porque o motivo da saída também nomeia o pedido.
      # É o recorte útil: a pergunta "o que houve com esse pedido?" quer as
      # duas linhas.
      conn = get(conn, ~p"/auditoria?busca=#{Orders.code(order)}")
      assert %{entries: entries} = inertia_props(conn)

      assert [:order_registered, :stock_out] =
               entries |> Enum.map(& &1.action) |> Enum.sort()
    end

    test "sem nada registrado a tela abre vazia, não quebra", %{conn: conn} do
      conn = get(conn, ~p"/auditoria")

      assert %{entries: [], page: %{count: 0, pages: 1}} = inertia_props(conn)
    end
  end
end
