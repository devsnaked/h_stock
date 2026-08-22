defmodule Web.DeliveryControllerTest do
  @moduledoc """
  As telas do entregador: o que ele abre, o que ele não abre e o despacho
  feito do balcão.
  """
  use Web.ConnCase, async: true

  import Inertia.Testing
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

  describe "tela de entregas" do
    test "lista só os pedidos que estão com o entregador", %{conn: conn} do
      employee = user_fixture()
      driver = driver_fixture()
      outro = driver_fixture()

      meu = order_fixture(employee)
      alheio = order_fixture(employee)

      {:ok, _} = Orders.assign_driver(meu, driver.id, actor: employee)
      {:ok, _} = Orders.assign_driver(alheio, outro.id, actor: employee)

      conn = conn |> log_in(driver) |> get(~p"/entregas")

      assert %{orders: [order], deliveredToday: 0} = inertia_props(conn)
      assert order.id == meu.id
      # O entregador confere o que vai na sacola, então os itens vêm junto.
      assert [_item] = order.items
    end

    test "entregador é mandado para as entregas ao abrir o balcão", %{conn: conn} do
      conn = conn |> log_in(driver_fixture()) |> get(~p"/")

      assert redirected_to(conn) == "/entregas"
    end

    test "entregador não abre a tela de novo pedido", %{conn: conn} do
      conn = conn |> log_in(driver_fixture()) |> get(~p"/pedidos/novo")

      assert redirected_to(conn) == "/entregas"
    end

    test "quem é do balcão não fica na tela de entregas", %{conn: conn} do
      conn = conn |> log_in(user_fixture()) |> get(~p"/entregas")

      assert redirected_to(conn) =~ "/pedidos"
    end
  end

  describe "entregador escolhido no formulário da venda" do
    test "a tela de novo pedido traz os entregadores", %{conn: conn} do
      driver = driver_fixture()

      conn = conn |> log_in(user_fixture()) |> get(~p"/pedidos/novo")

      assert %{drivers: [%{id: id}]} = inertia_props(conn)
      assert id == driver.id
    end

    test "registrar já com entregador põe o pedido na lista dele", %{conn: conn} do
      employee = user_fixture()
      driver = driver_fixture()
      product = product_fixture(stock_grams: 5_000)

      conn =
        conn
        |> log_in(employee)
        |> post(~p"/pedidos", %{
          "items" => [
            %{
              "product_id" => product.id,
              "batch_id" => batch_of(product).id,
              "quantity" => "100",
              "unit" => "g"
            }
          ],
          "driver_id" => driver.id
        })

      assert %{id: id} = redirected_params(conn)
      assert Ash.get!(Orders.Order, id, authorize?: false).driver_id == driver.id
    end

    test "retirada no balcão ignora o entregador escolhido", %{conn: conn} do
      employee = user_fixture()
      driver = driver_fixture()
      product = product_fixture(stock_grams: 5_000)

      conn =
        conn
        |> log_in(employee)
        |> post(~p"/pedidos", %{
          "items" => [
            %{
              "product_id" => product.id,
              "batch_id" => batch_of(product).id,
              "quantity" => "100",
              "unit" => "g"
            }
          ],
          "needs_delivery" => false,
          "driver_id" => driver.id
        })

      # Desligar a entrega é o último gesto e manda: o pedido é registrado
      # como retirada, sem entregador, em vez de virar erro de formulário.
      assert %{id: id} = redirected_params(conn)
      order = Ash.get!(Orders.Order, id, authorize?: false)
      assert order.delivery_status == :not_required
      refute order.driver_id
    end
  end

  describe "despacho pelo balcão" do
    test "manda o pedido para o entregador", %{conn: conn} do
      employee = user_fixture()
      driver = driver_fixture()
      order = order_fixture(employee)

      conn =
        conn
        |> log_in(employee)
        |> post(~p"/pedidos/#{order.id}/entregador", %{"driver_id" => driver.id})

      assert redirected_to(conn) == "/pedidos/#{order.id}"

      order = Ash.get!(Orders.Order, order.id, authorize?: false)
      assert order.driver_id == driver.id
    end

    test "a tela do pedido já traz a lista de entregadores", %{conn: conn} do
      employee = user_fixture()
      driver = driver_fixture()
      order = order_fixture(employee)

      conn = conn |> log_in(employee) |> get(~p"/pedidos/#{order.id}")

      assert %{drivers: [%{id: id, name: _}]} = inertia_props(conn)
      assert id == driver.id
    end

    test "o entregador não recebe lista para redistribuir o pedido", %{conn: conn} do
      employee = user_fixture()
      driver = driver_fixture()
      order = order_fixture(employee)
      {:ok, order} = Orders.assign_driver(order, driver.id, actor: employee)

      conn = conn |> log_in(driver) |> get(~p"/pedidos/#{order.id}")

      assert %{drivers: []} = inertia_props(conn)
    end

    test "escolher quem não é entregador devolve erro", %{conn: conn} do
      employee = user_fixture()
      colega = user_fixture()
      order = order_fixture(employee)

      conn =
        conn
        |> log_in(employee)
        |> post(~p"/pedidos/#{order.id}/entregador", %{"driver_id" => colega.id})

      assert redirected_to(conn) == "/pedidos/#{order.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      refute Ash.get!(Orders.Order, order.id, authorize?: false).driver_id
    end

    test "entregador marca a entrega pela tela do pedido", %{conn: conn} do
      employee = user_fixture()
      driver = driver_fixture()
      order = order_fixture(employee)
      {:ok, order} = Orders.assign_driver(order, driver.id, actor: employee)

      conn =
        conn
        |> log_in(driver)
        |> post(~p"/pedidos/#{order.id}/entrega/entregue")

      assert redirected_to(conn) == "/pedidos/#{order.id}"
      assert Ash.get!(Orders.Order, order.id, authorize?: false).delivery_status == :delivered
    end
  end
end
