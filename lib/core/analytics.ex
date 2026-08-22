defmodule Core.Analytics do
  @moduledoc """
  Os números da loja para o painel, **uma categoria por função**.

  A divisão não é estética: cada bloco do painel busca o próprio dado quando
  entra na tela (`inertia_optional` + `WhenVisible`), e é esta separação que
  permite isso. Cada função lê só os pedidos que a sua pergunta precisa, com
  as colunas que ela usa — o ranking de produtos carrega os itens, o quadro de
  entrega não; o resumo de vendas nem toca em produto.

  Tudo é lido **com o ator**, então a mesma função devolve a loja inteira para
  o admin e só os próprios pedidos para o funcionário comum, sem nenhum `if`
  aqui dentro. É a policy do `Core.Orders.Order` que decide.

  Custo e lucro só entram com `costs?`, a mesma régua de quem enxerga custo em
  qualquer outra tela.

  **Qual seção existe para quem é outra pergunta**, e ela não se responde aqui:
  é `Core.Accounts.Permissions`. Quem chama percorre as seções liberadas para o
  ator e só pede aquelas (é o que o `Web.DashboardController` faz), então uma
  seção sem permissão não chega a virar consulta. Chamada nova a este módulo —
  um relatório, uma API — precisa fazer o mesmo: aqui dentro não há filtro por
  seção.

  As contas são feitas em memória de propósito: um dia, uma semana ou um mês
  de uma loja cabem folgados, e escrever isto como agregação SQL custaria
  legibilidade sem devolver velocidade que faça diferença.
  """

  require Ash.Query

  alias Core.Clock
  alias Core.Inventory.Product
  alias Core.Orders.Order

  @doc """
  Vendas do período: a série por dia, os totais e o que foi cancelado.

  Os dias sem venda entram zerados — um buraco no meio do gráfico é ruído; um
  zero é informação.
  """
  def sales(actor, from, to, costs?) do
    orders = orders(actor, from, to, [:status, :total, :cost_total, :discount_total])
    sold = Enum.filter(orders, &(&1.status == :completed))
    by_day = Enum.group_by(sold, &local_date(&1.inserted_at))

    daily =
      from
      |> Date.range(to)
      |> Enum.map(fn date ->
        day = Map.get(by_day, date, [])

        base = %{
          date: Date.to_iso8601(date),
          orders: length(day),
          revenue: sum(day, & &1.total),
          discount: sum(day, & &1.discount_total)
        }

        with_costs(base, costs?, fn ->
          %{cost: sum(day, & &1.cost_total), profit: sum(day, &profit_of/1)}
        end)
      end)

    cancelled = Enum.filter(orders, &(&1.status == :cancelled))
    revenue = sum(sold, & &1.total)

    %{
      daily: daily,
      totals:
        %{
          orders: length(sold),
          revenue: revenue,
          discount: sum(sold, & &1.discount_total),
          ticket: if(sold == [], do: 0.0, else: revenue / length(sold))
        }
        |> with_costs(costs?, fn ->
          %{cost: sum(sold, & &1.cost_total), profit: sum(sold, &profit_of/1)}
        end),
      cancellations: %{count: length(cancelled), total: sum(cancelled, & &1.total)}
    }
  end

  @doc """
  Pedidos por hora do dia. Responde "a que horas a loja vende?", que é o
  número que decide escala de gente no balcão.
  """
  def hours(actor, from, to) do
    by_hour =
      actor
      |> orders(from, to, [:status, :total])
      |> Enum.filter(&(&1.status == :completed))
      |> Enum.group_by(&local_hour(&1.inserted_at))

    Enum.map(0..23, fn hour ->
      slot = Map.get(by_hour, hour, [])

      %{hour: hour, orders: length(slot), revenue: sum(slot, & &1.total)}
    end)
  end

  @doc """
  Os dez produtos que mais renderam no período, com peso vendido — o ranking
  que diz o que repor primeiro. É a única categoria que carrega os itens.
  """
  def products(actor, from, to, costs?) do
    actor
    |> orders(from, to, [:status], load: [:items])
    |> Enum.filter(&(&1.status == :completed))
    |> Enum.flat_map(& &1.items)
    |> Enum.group_by(& &1.product_name)
    |> Enum.map(fn {name, items} ->
      base = %{
        name: name,
        grams: sum(items, & &1.grams),
        revenue: sum(items, & &1.total),
        orders: items |> Enum.map(& &1.order_id) |> Enum.uniq() |> length()
      }

      with_costs(base, costs?, fn ->
        %{profit: sum(items, &Decimal.sub(&1.total, &1.total_cost))}
      end)
    end)
    |> Enum.sort_by(& &1.revenue, :desc)
    |> Enum.take(10)
  end

  @doc "Quanto cada pessoa do balcão registrou no período."
  def team(actor, from, to) do
    actor
    |> orders(from, to, [:status, :total, :user_id], load: [:user])
    |> Enum.filter(&(&1.status == :completed))
    |> Enum.group_by(&name_of(&1.user))
    |> Enum.map(fn {name, sold} ->
      %{name: name, orders: length(sold), revenue: sum(sold, & &1.total)}
    end)
    |> Enum.sort_by(& &1.revenue, :desc)
  end

  @doc """
  Entrega: o que está na rua **agora** e como foi no período — quantos em cada
  estágio, quantos sem entregador, quanto tempo leva do registro à porta do
  cliente, e o mesmo por entregador.

  A fila de agora não depende do recorte de tempo: um pedido de ontem que
  ainda não chegou continua sendo problema hoje.
  """
  def delivery(actor, from, to) do
    orders =
      actor
      |> orders(from, to, [:status, :delivery_status, :delivered_at, :driver_id], load: [:driver])
      |> Enum.filter(&(&1.status == :completed))

    to_deliver = Enum.filter(orders, &(&1.delivery_status != :not_required))
    delivered = Enum.filter(to_deliver, &(&1.delivery_status == :delivered))

    %{
      now: queue(actor),
      summary: %{
        pending: count_by(to_deliver, :pending),
        out_for_delivery: count_by(to_deliver, :out_for_delivery),
        delivered: length(delivered),
        pickup: Enum.count(orders, &(&1.delivery_status == :not_required)),
        # Fila sem dono: é o número que mostra pedido pronto parado no balcão.
        unassigned:
          Enum.count(to_deliver, &(&1.driver_id == nil and &1.delivery_status != :delivered)),
        average_minutes: average_minutes(delivered)
      },
      drivers: drivers(to_deliver)
    }
  end

  # A rua agora: o que já foi vendido e ainda não chegou, e o que foi
  # confirmado hoje. São contagens no banco — não passam pela lista do
  # período, justamente porque não são do período.
  defp queue(actor) do
    {day_start, day_end} = Clock.today_range()

    %{
      to_deliver: Order |> Ash.Query.for_read(:to_deliver, %{}, actor: actor) |> Ash.count!(),
      delivered_today:
        Order
        |> Ash.Query.filter(
          status == :completed and delivery_status == :delivered and
            delivered_at >= ^day_start and delivered_at < ^day_end
        )
        |> Ash.count!(actor: actor)
    }
  end

  defp drivers(orders) do
    orders
    |> Enum.filter(&(&1.driver_id != nil))
    |> Enum.group_by(&name_of(&1.driver))
    |> Enum.map(fn {name, assigned} ->
      delivered = Enum.filter(assigned, &(&1.delivery_status == :delivered))

      %{
        name: name,
        assigned: length(assigned),
        delivered: length(delivered),
        on_the_way: count_by(assigned, :out_for_delivery),
        average_minutes: average_minutes(delivered)
      }
    end)
    |> Enum.sort_by(& &1.delivered, :desc)
  end

  @doc """
  Estoque **agora** — é a única categoria que não olha o período: saldo é do
  momento em que se pergunta, não do intervalo escolhido.
  """
  def stock(actor, costs?) do
    products =
      Product
      |> Ash.Query.filter(active == true)
      |> Ash.Query.load(:stock_cost_value)
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!(actor: actor)

    low = Enum.filter(products, &(not Decimal.gt?(&1.stock_grams, &1.min_stock_grams)))

    base = %{
      active: length(products),
      low: length(low),
      low_products:
        low
        |> Enum.take(5)
        |> Enum.map(&%{id: &1.id, name: &1.name, stock_grams: number(&1.stock_grams)})
    }

    with_costs(base, costs?, fn ->
      %{
        value: sum(products, &(&1.stock_cost_value || Decimal.new(0))),
        # Os cinco produtos com mais dinheiro parado: é neles que uma compra
        # errada dói.
        top_value:
          products
          |> Enum.map(&%{name: &1.name, value: number(&1.stock_cost_value || Decimal.new(0))})
          |> Enum.sort_by(& &1.value, :desc)
          |> Enum.take(5)
      }
    end)
  end

  @doc """
  Os últimos pedidos do período — a única seção que devolve registros, e não
  contas: quem chama serializa (`Web.Serializers.order/2`, que é onde custo e
  lucro param para quem não é do grupo do estoque).

  Oito é o que caberia numa rolada de polegar; para a lista inteira a tela
  manda para `/pedidos` com o mesmo recorte.
  """
  def recent(actor, from, to) do
    {start_at, end_at} = Clock.range(from, to)

    Order
    |> Ash.Query.filter(inserted_at >= ^start_at and inserted_at < ^end_at)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(8)
    |> Ash.Query.load([:user, :driver, :items_count])
    |> Ash.read!(actor: actor)
  end

  # `select` em vez de trazer a linha inteira: o painel lê muitos pedidos e
  # nenhum deles precisa de observação, endereço ou coordenada.
  defp orders(actor, from, to, fields, opts \\ []) do
    {start_at, end_at} = Clock.range(from, to)

    Order
    |> Ash.Query.filter(inserted_at >= ^start_at and inserted_at < ^end_at)
    |> Ash.Query.select([:id, :inserted_at | fields])
    |> Ash.Query.load(Keyword.get(opts, :load, []))
    |> Ash.read!(actor: actor)
  end

  defp with_costs(base, false, _fun), do: base
  defp with_costs(base, true, fun), do: Map.merge(base, fun.())

  defp profit_of(order), do: Decimal.sub(order.total, order.cost_total)

  defp count_by(orders, status), do: Enum.count(orders, &(&1.delivery_status == status))

  # Média em minutos do registro até a entrega. `nil` quando ainda não houve
  # entrega nenhuma — a tela mostra um traço em vez de "0 min", que mentiria.
  defp average_minutes([]), do: nil

  defp average_minutes(orders) do
    minutes =
      Enum.map(orders, fn order ->
        DateTime.diff(order.delivered_at, order.inserted_at, :minute)
      end)

    round(Enum.sum(minutes) / length(minutes))
  end

  defp sum(records, fun) do
    records
    |> Enum.reduce(Decimal.new(0), &Decimal.add(fun.(&1), &2))
    |> number()
  end

  defp number(%Decimal{} = decimal), do: Decimal.to_float(decimal)

  defp name_of(%{name: name}), do: name
  defp name_of(_other), do: "—"

  defp local_date(datetime), do: datetime |> shift() |> DateTime.to_date()
  defp local_hour(datetime), do: datetime |> shift() |> Map.fetch!(:hour)

  # O gráfico é do dia da loja: uma venda das 21h em São Paulo não pode
  # aparecer no dia seguinte só porque o banco guarda UTC.
  defp shift(datetime), do: DateTime.shift_zone!(datetime, Clock.timezone())
end
