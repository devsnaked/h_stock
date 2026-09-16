defmodule Mix.Tasks.Demo.Orders do
  @shortdoc "Gera vendas de exemplo para ver o painel com dados"

  @moduledoc """
  Preenche a loja com um mês de vendas fictícias.

      mix demo.orders            # 30 dias
      mix demo.orders --dias 60

  Existe porque o painel só tem o que mostrar quando existe venda: numa base
  recém-criada os gráficos aparecem vazios e não dá para avaliar a tela. As
  vendas saem espalhadas pelos dias e pelas horas do expediente, com entregas
  em estágios diferentes, algumas retiradas no balcão e alguns cancelamentos —
  é o que faz cada gráfico ter forma.

  A loja de exemplo vem inteira: se faltarem produtos, funcionário ou
  entregador, a tarefa os cria antes de vender (`Core.Demo`, senha
  `Pass@123!`) — os mesmos que os seeds criam em desenvolvimento.

  **Só roda fora de produção.** E é aditivo: rodar duas vezes gera mais
  vendas, não repõe as anteriores.

  A data de cada pedido é escrita direto na tabela depois de registrado:
  `inserted_at` é `create_timestamp`, e o domínio não deixa (bem) que uma
  venda escolha quando aconteceu. Para dado de mentira serve; nenhuma outra
  parte do sistema faz isso.
  """
  use Mix.Task

  import Ecto.Query

  require Ash.Query

  alias Core.Accounts.User
  alias Core.Inventory
  alias Core.Inventory.Product
  alias Core.Orders

  @impl Mix.Task
  def run(args) do
    if Mix.env() == :prod do
      Mix.raise("mix demo.orders não roda em produção — são vendas de mentira.")
    end

    {opts, _rest} = OptionParser.parse!(args, strict: [dias: :integer])
    days = Keyword.get(opts, :dias, 30)

    Mix.Task.run("app.start")
    # Mesma semente sempre: rodar de novo dá a mesma loja, o que ajuda a
    # comparar duas versões da tela.
    :rand.seed(:exsss, {42, 42, 42})

    ensure_demo_cast()

    employees = employees()
    drivers = drivers()
    products = products_with_stock()

    count =
      Enum.reduce(days..0//-1, 0, fn ago, acc ->
        date = Date.add(Core.Clock.today(), -ago)
        acc + Enum.count(orders_for(date, employees, drivers, products), & &1)
      end)

    Mix.shell().info("#{count} vendas de exemplo criadas nos últimos #{days} dias.")
    Mix.shell().info("Abra / e troque o período para 'Mês' para ver os gráficos.")
  end

  # Domingo a loja abre menos; sábado é o dia cheio. Sem essa variação todos
  # os gráficos sairiam retos, e reta não mostra se a tela sabe desenhar.
  defp orders_for(date, employees, drivers, products) do
    volume =
      case Date.day_of_week(date) do
        7 -> 0..3
        6 -> 6..12
        _ -> 3..8
      end

    for _ <- 1..Enum.random(volume)//1 do
      create_order(date, Enum.random(employees), drivers, products)
    end
  end

  defp create_order(date, employee, drivers, products) do
    items =
      products
      |> Enum.take_random(Enum.random(1..3))
      |> Enum.map(fn product ->
        # O lote mais cheio, e não o mais antigo: a venda de exemplo não pode
        # esbarrar num lote com 80g de sobra e derrubar o dia inteiro.
        batch = product |> open_batches() |> Enum.max_by(& &1.remaining_grams, Decimal)

        %{
          product_id: product.id,
          batch_id: batch.id,
          grams: Decimal.new(Enum.random(1..12) * 100)
        }
      end)

    delivery? = Enum.random(1..10) > 3

    attrs = %{
      items: items,
      customer_name: Enum.random(customers()),
      delivery_status: if(delivery?, do: :pending, else: :not_required),
      discount_type: Enum.random([:none, :none, :none, :percent, :amount]),
      discount_value: Decimal.new(Enum.random(1..10)),
      delivery_address: if(delivery?, do: Enum.random(addresses()))
    }

    attrs =
      if delivery? do
        {lat, lon} = Enum.random(coordinates())
        Map.merge(attrs, %{delivery_lat: Decimal.new(lat), delivery_lon: Decimal.new(lon)})
      else
        attrs
      end

    case Orders.register_order(attrs, actor: employee) do
      {:ok, order} ->
        order
        |> advance_delivery(date, drivers, employee)
        |> maybe_cancel(employee)
        |> backdate(date)

        true

      # Estoque acabou no meio da geração: a venda que falta não vale
      # interromper o resto do mês.
      {:error, _error} ->
        false
    end
  end

  # A entrega anda conforme a idade do pedido: o que é de ontem para trás já
  # chegou, o de hoje está no meio do caminho.
  defp advance_delivery(order, date, drivers, employee) do
    hoje? = Date.compare(date, Core.Clock.today()) == :eq

    cond do
      order.delivery_status != :pending ->
        order

      drivers == [] ->
        order

      hoje? ->
        {:ok, order} = Orders.assign_driver(order, Enum.random(drivers).id, actor: employee)

        if Enum.random(1..2) == 1 do
          {:ok, order} = Orders.mark_out_for_delivery(order, actor: employee)
          order
        else
          order
        end

      true ->
        {:ok, order} = Orders.assign_driver(order, Enum.random(drivers).id, actor: employee)
        {:ok, order} = Orders.mark_out_for_delivery(order, actor: employee)
        {:ok, order} = Orders.mark_delivered(order, actor: employee)
        order
    end
  end

  # Um cancelamento a cada vinte vendas: o suficiente para o cartão de
  # cancelados não ficar zerado, longe de virar a regra.
  defp maybe_cancel(order, employee) do
    if Enum.random(1..20) == 1 do
      {:ok, order} = Orders.cancel_order(order, %{reason: "Cliente desistiu"}, actor: employee)
      order
    else
      order
    end
  end

  # As horas saem do expediente (9h às 19h), com o pico no fim da tarde — é o
  # que dá forma ao gráfico de movimento por hora.
  defp backdate(order, date) do
    hour = Enum.random([9, 10, 11, 11, 12, 14, 15, 16, 17, 17, 18, 18, 19])
    minute = Enum.random(0..59)

    {:ok, naive} = NaiveDateTime.new(date, Time.new!(hour, minute, 0))
    {:ok, local} = DateTime.from_naive(naive, Core.Clock.timezone())
    at = DateTime.shift_zone!(local, "Etc/UTC")

    fields =
      [inserted_at: at]
      |> put_when(order.assigned_at, :assigned_at, DateTime.add(at, 20, :minute))
      |> put_when(order.out_for_delivery_at, :out_for_delivery_at, DateTime.add(at, 30, :minute))
      |> put_when(
        order.delivered_at,
        :delivered_at,
        DateTime.add(at, Enum.random(35..90), :minute)
      )
      |> put_when(order.cancelled_at, :cancelled_at, DateTime.add(at, 45, :minute))

    Core.Repo.update_all(
      from(o in "orders", where: o.id == type(^order.id, :binary_id)),
      set: fields
    )

    order
  end

  defp put_when(fields, nil, _key, _value), do: fields
  defp put_when(fields, _existing, key, value), do: Keyword.put(fields, key, value)

  # A equipe e o catálogo do exemplo são os mesmos que os seeds criam em
  # desenvolvimento — moram no `Core.Demo` para não existirem em dois lugares.
  defp ensure_demo_cast do
    case Core.Demo.admin() do
      nil -> Mix.raise("Nenhum administrador. Rode `mix run priv/repo/seeds.exs` antes.")
      admin -> Core.Demo.ensure_cast(admin)
    end
  end

  defp employees do
    case Ash.read!(User, authorize?: false) |> Enum.filter(&(&1.role in [:admin, :employee])) do
      [] -> Mix.raise("Nenhum usuário de balcão. Rode `mix run priv/repo/seeds.exs` antes.")
      users -> users
    end
  end

  defp drivers do
    User
    |> Ash.Query.for_read(:drivers, %{}, authorize?: false)
    |> Ash.read!(authorize?: false)
  end

  # Estoque farto antes de começar: sem isso a geração para no meio do mês
  # com "estoque insuficiente", e os últimos dias sairiam vazios.
  defp products_with_stock do
    products =
      Product
      |> Ash.Query.filter(active == true)
      |> Ash.read!(authorize?: false)

    Enum.map(products, fn product ->
      {:ok, product} =
        Inventory.add_stock(
          product,
          Decimal.new(200_000),
          Decimal.mult(product.price_per_gram, Decimal.new("0.55")),
          %{label: "Lote de demonstração", reason: "Carga para dados de exemplo"},
          authorize?: false
        )

      product
    end)
  end

  defp open_batches(product) do
    product.id
    |> Inventory.list_batches_for_product!(authorize?: false)
    |> Enum.filter(&Decimal.positive?(&1.remaining_grams))
  end

  defp customers do
    [
      "Dona Marta",
      "Seu Zé",
      "Padaria Aurora",
      "Restaurante Bom Prato",
      "Cláudia Menezes",
      "Mercado do Bairro",
      nil
    ]
  end

  defp addresses do
    [
      "Rua das Flores, 100 — Centro",
      "Avenida Brasil, 2450 — Jardim América",
      "Rua Sete de Setembro, 33 — Centro",
      "Travessa São João, 12 — Vila Nova",
      "Alameda dos Ipês, 780 — Bela Vista"
    ]
  end

  # Pontos reais espalhados por São Paulo: o mapa do pedido precisa cair em
  # algum lugar que exista.
  defp coordinates do
    [
      {"-23.55052", "-46.633308"},
      {"-23.561414", "-46.655881"},
      {"-23.543138", "-46.642514"},
      {"-23.588", "-46.632"},
      {"-23.52", "-46.61"}
    ]
  end
end
