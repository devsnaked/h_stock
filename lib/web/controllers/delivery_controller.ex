defmodule Web.DeliveryController do
  @moduledoc """
  O app do entregador: a lista do que está na mão dele agora.

  Só uma tela, e de propósito — quem está na rua abre o celular para saber
  para onde ir e marcar que chegou. O que já foi entregue sai da lista; o
  histórico é assunto do balcão.

  A policy do `Core.Orders.Order` já limita o entregador aos pedidos dele, e
  a leitura aqui é pelo `:for_driver` justamente para a lista não depender
  disso — são duas travas para a mesma coisa, e a de fora é barata.
  """
  use Web, :controller

  require Ash.Query

  alias Core.Orders.Order
  alias Web.Serializers

  def index(conn, _params) do
    user = actor(conn)

    orders =
      Order
      |> Ash.Query.for_read(:for_driver, %{driver_id: user.id}, actor: user)
      # Quem saiu primeiro chega primeiro: a ordem da lista é a ordem em que
      # os pedidos foram despachados.
      |> Ash.Query.sort(assigned_at: :asc)
      |> Ash.Query.load([:user, :items])
      |> Ash.read!(actor: user)

    # "Hoje" é o dia da loja, não o UTC — ver `Core.Clock`.
    {day_start, day_end} = Core.Clock.today_range()

    delivered_today =
      Order
      |> Ash.Query.filter(
        driver_id == ^user.id and delivery_status == :delivered and
          delivered_at >= ^day_start and delivered_at < ^day_end
      )
      |> Ash.count!(actor: user)

    conn
    |> assign_prop(:orders, Enum.map(orders, &Serializers.order(&1, with_items: true)))
    |> assign_prop(:delivered_today, delivered_today)
    |> render_inertia("Deliveries")
  end
end
