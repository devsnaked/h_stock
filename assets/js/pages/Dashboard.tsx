import * as React from "react";
import { Link, WhenVisible, usePage } from "@inertiajs/react";
import {
  AlertTriangle,
  Bike,
  Boxes,
  CalendarClock,
  ChevronDown,
  Clock3,
  MapPin,
  Receipt,
  TrendingUp,
  Users,
} from "lucide-react";
import { AppLayout } from "@/layouts/AppLayout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { DateRangePicker, type Range } from "@/components/DateRangePicker";
import { DeliveryBadge } from "@/components/DeliveryBadge";
import { OrdersMap } from "@/components/OrdersMap";
import {
  ChartCard,
  ChartTable,
  DailySalesChart,
  HourlyChart,
  RankingChart,
  SERIES,
} from "@/components/charts";
import { useCurrentUser } from "@/hooks/useAuth";
import { cn } from "@/lib/utils";
import { dateLabel, dateTimeLabel, money, monthLabel, weight } from "@/lib/format";
import type {
  DashboardSection,
  DeliveryAnalytics,
  HourAnalytics,
  Order,
  ProductAnalytics,
  ReceivablesAnalytics,
  SalesAnalytics,
  StockAnalytics,
  TeamAnalytics,
} from "@/types";

type Props = {
  range: Range;
  today: string;
  /** Quem enxerga custo e lucro. */
  costs: boolean;
  /** As seções liberadas para quem está olhando, na ordem da tela. */
  sections: DashboardSection[];
};

/**
 * Painel da loja: **só análise**.
 *
 * Nada de operação aqui — registrar pedido é na tela de pedidos, e os números
 * do dia aparecem dentro das categorias, não repetidos num cabeçalho.
 *
 * **Cada categoria busca o próprio dado quando chega perto da tela**
 * (`WhenVisible` de um lado, `inertia_optional` do outro): a primeira
 * resposta é curta, uma consulta pesada não segura as outras, e categoria
 * fechada nem chega a ser consultada no banco.
 *
 * **A tela não sabe de cor quais categorias existem**: ela desenha as que
 * vierem em `sections`. Categoria fora da lista não é escondida com CSS — o
 * prop dela não existe do outro lado, então não há o que pedir nem o que
 * mostrar.
 *
 * Trocar o período recarrega a página sem preservar estado (ver
 * `DateRangePicker`), de propósito: os blocos remontam e cada um vai buscar
 * de novo o seu recorte, em vez de mostrar o número do período anterior.
 */
export default function Dashboard({ range, today, costs, sections }: Props) {
  const user = useCurrentUser();
  const isToday = range.from === today && range.to === today;
  const periodo = isToday ? "hoje" : "no período";
  const has = (section: DashboardSection) => sections.includes(section);

  return (
    <AppLayout title={`Olá, ${user.name.split(" ")[0]}`} subtitle="Análise da loja">
      <div className="space-y-4">
        {/* O seletor de período manda em tudo que vem abaixo, e por isso é a
            primeira coisa da tela. */}
        <DateRangePicker range={range} today={today} />

        {sections.length === 0 && (
          <Empty>
            Nenhuma seção de dados foi liberada para você. Fale com o
            administrador.
          </Empty>
        )}

        {has("map") && (
          <Category
            title="Mapa"
            hint={`Onde os pedidos ${periodo} foram parar.`}
            icon={MapPin}
            data="map"
            lines={2}
          >
            <Mapa />
          </Category>
        )}

        {has("sales") && (
          <Category
            title="Vendas"
            hint={`Faturamento, lucro e o que foi cancelado ${periodo}.`}
            icon={TrendingUp}
            data="sales"
            lines={3}
          >
            <Sales costs={costs} />
          </Category>
        )}

        {has("receivables") && (
          <Category
            title="A prazo"
            hint={`O que os clientes devem, e o que foi vendido a prazo ${periodo}.`}
            icon={CalendarClock}
            data="receivables"
            lines={3}
            action={
              <Link
                href="/pedidos?pagamento=pendente"
                className="shrink-0 text-xs font-medium underline underline-offset-4"
              >
                não pagos
              </Link>
            }
          >
            <Receivables />
          </Category>
        )}

        {has("hours") && (
          <Category title="Horários" hint="A que horas a loja vende." icon={Clock3} data="hours">
            <Hours />
          </Category>
        )}

        {has("products") && (
          <Category
            title="Produtos"
            hint="O que mais saiu — e o que repor primeiro."
            icon={Boxes}
            data="products"
            lines={2}
          >
            <Products costs={costs} />
          </Category>
        )}

        {has("team") && (
          <Category title="Equipe" hint="Quem registrou as vendas." icon={Users} data="team">
            <Team />
          </Category>
        )}

        {has("delivery") && (
          <Category
            title="Entrega"
            hint="A fila, o tempo até a porta e quem levou."
            icon={Bike}
            data="delivery"
            lines={2}
          >
            <Delivery />
          </Category>
        )}

        {has("stock") && (
          <Category
            title="Estoque"
            hint="Saldo de agora — este não muda com o período."
            icon={AlertTriangle}
            data="stock"
            lines={2}
          >
            <Stock />
          </Category>
        )}

        {has("recent") && (
          <Category
            title="Últimos pedidos"
            hint={`Os mais recentes ${periodo}.`}
            icon={Receipt}
            data="recent"
            lines={4}
            action={
              <Link
                href={`/pedidos?de=${range.from}&ate=${range.to}`}
                className="shrink-0 text-xs font-medium underline underline-offset-4"
              >
                ver todos
              </Link>
            }
          >
            <Recent />
          </Category>
        )}
      </div>
    </AppLayout>
  );
}

/**
 * Um bloco do painel: cabeçalho da categoria e o conteúdo, que só é buscado
 * quando o bloco se aproxima da área visível.
 *
 * O cabeçalho inteiro é o botão de abrir e fechar — no celular, um alvo
 * grande vale mais que uma setinha. **Fechada, a categoria não busca nada**:
 * o `WhenVisible` nem chega a ser montado, então a consulta não sai do
 * servidor. Reabrir busca na hora.
 *
 * `buffer` adianta a busca em 300px, então na rolagem normal o dado costuma
 * chegar antes do bloco — o esqueleto é o plano B, não a regra.
 */
const Category: React.FC<{
  title: string;
  hint: string;
  icon: React.ComponentType<{ className?: string }>;
  /** A seção que este bloco pede ao servidor — e o nome do prop dela. */
  data: DashboardSection;
  lines?: number;
  action?: React.ReactNode;
  children: React.ReactNode;
}> = ({ title, hint, icon: Icon, data, lines = 1, action, children }) => {
  const [open, setOpen] = useCollapsible(data);

  return (
    <section className="space-y-2 pt-2">
      <div className="flex items-center justify-between gap-3">
        <button
          type="button"
          onClick={() => setOpen(!open)}
          aria-expanded={open}
          aria-controls={`categoria-${data}`}
          className="-ml-1 flex min-w-0 flex-1 items-center gap-2 rounded-lg p-1 text-left"
        >
          <ChevronDown
            className={cn(
              "size-4 shrink-0 text-muted-foreground transition-transform",
              !open && "-rotate-90",
            )}
          />

          <span className="min-w-0">
            <span className="flex items-center gap-2 text-sm font-semibold">
              <Icon className="size-4 text-muted-foreground" />
              {title}
            </span>
            <span className="block truncate text-xs text-muted-foreground">{hint}</span>
          </span>
        </button>

        {action}
      </div>

      <div id={`categoria-${data}`} hidden={!open}>
        {open && (
          <WhenVisible data={data} buffer={300} fallback={<Skeleton lines={lines} />}>
            <div className="space-y-3">{children}</div>
          </WhenVisible>
        )}
      </div>
    </section>
  );
};

const STORAGE_PREFIX = "h_stock:painel:";

/**
 * Aberto ou fechado, lembrado entre visitas.
 *
 * A escolha é de quem usa a tela, e refazer a mesma dobra toda manhã seria
 * trabalho à toa — então ela mora no `localStorage`, por categoria. Guardamos
 * só o que foge do padrão (fechado), para uma categoria nova nascer aberta.
 *
 * `localStorage` pode não existir (navegador com armazenamento bloqueado);
 * nesse caso a tela funciona igual, só não lembra.
 */
function useCollapsible(key: string): [boolean, (open: boolean) => void] {
  const [open, setOpen] = React.useState(true);

  React.useEffect(() => {
    try {
      setOpen(window.localStorage.getItem(STORAGE_PREFIX + key) !== "fechado");
    } catch {
      // sem armazenamento: segue aberto
    }
  }, [key]);

  const change = React.useCallback(
    (next: boolean) => {
      setOpen(next);

      try {
        if (next) window.localStorage.removeItem(STORAGE_PREFIX + key);
        else window.localStorage.setItem(STORAGE_PREFIX + key, "fechado");
      } catch {
        // idem
      }
    },
    [key],
  );

  return [open, change];
}

/** Espaço reservado enquanto a categoria não chegou. */
const Skeleton: React.FC<{ lines: number }> = ({ lines }) => (
  <div className="space-y-3" aria-hidden>
    {Array.from({ length: lines }).map((_, index) => (
      <div
        key={index}
        className="h-28 animate-pulse rounded-xl border border-border bg-muted/60"
      />
    ))}
  </div>
);

/** Lê um prop de categoria; `undefined` enquanto a requisição não voltou. */
function useCategory<T>(key: string): T | undefined {
  return usePage().props[key] as T | undefined;
}

const Sales: React.FC<{ costs: boolean }> = ({ costs }) => {
  const sales = useCategory<SalesAnalytics>("sales");
  if (!sales) return null;

  const { daily, totals, cancellations } = sales;

  if (totals.orders === 0) {
    return <Empty>Nenhuma venda neste período.</Empty>;
  }

  return (
    <>
      <div className="grid grid-cols-2 gap-3">
        <Stat
          label="Faturamento"
          value={money(totals.revenue)}
          hint={`${totals.orders} ${totals.orders === 1 ? "pedido" : "pedidos"}`}
        />
        <Stat
          label="Ticket médio"
          value={money(totals.ticket)}
          hint={
            totals.discount > 0
              ? `${money(totals.discount)} em descontos`
              : "nenhum desconto dado"
          }
        />
      </div>

      {totals.profit !== undefined && (
        <Stat
          label="Lucro"
          value={money(totals.profit)}
          hint={`${money(totals.cost ?? 0)} de custo da mercadoria`}
          icon={TrendingUp}
        />
      )}

      <ChartCard
        title="Vendas por dia"
        legend={[
          { label: "Faturamento", color: SERIES.neutral },
          ...(costs ? [{ label: "Lucro", color: SERIES.profit }] : []),
        ]}
      >
        <DailySalesChart data={daily} costs={costs} />
        <ChartTable
          columns={costs ? ["Dia", "Pedidos", "Vendas", "Lucro"] : ["Dia", "Pedidos", "Vendas"]}
          rows={daily.map((day) =>
            costs
              ? [dayLabel(day.date), day.orders, money(day.revenue), money(day.profit ?? 0)]
              : [dayLabel(day.date), day.orders, money(day.revenue)],
          )}
        />
      </ChartCard>

      <Stat
        label="Cancelados"
        value={String(cancellations.count)}
        hint={`${money(cancellations.total)} em vendas desfeitas`}
        alert={cancellations.count > 0}
      />
    </>
  );
};

/**
 * Vendas a prazo. O que está em aberto é de **agora** — conta que venceu mês
 * passado continua sendo dinheiro na rua hoje —, e só o quadro "no período"
 * segue o recorte de datas.
 */
const Receivables: React.FC = () => {
  const receivables = useCategory<ReceivablesAnalytics>("receivables");
  if (!receivables) return null;

  const { open, overdue, dueSoon, period, schedule, overdueOrders } = receivables;

  return (
    <>
      <div className="grid grid-cols-2 gap-3">
        <Stat
          to="/pedidos?pagamento=pendente"
          label="A receber"
          value={money(open.total)}
          hint={
            open.orders === 0
              ? "nenhuma venda em aberto"
              : `${open.orders} ${open.orders === 1 ? "venda em aberto" : "vendas em aberto"}`
          }
        />
        <Stat
          to="/pedidos?pagamento=pendente"
          label="Vencido"
          value={money(overdue.total)}
          hint={
            overdue.orders === 0
              ? "nada vencido"
              : `${overdue.orders} ${overdue.orders === 1 ? "venda passou" : "vendas passaram"} do dia`
          }
          alert={overdue.orders > 0}
        />
      </div>

      {dueSoon.orders > 0 && (
        <p className="rounded-lg border border-border bg-muted/50 p-3 text-xs">
          {money(dueSoon.total)} vence nos próximos 7 dias ({dueSoon.orders}{" "}
          {dueSoon.orders === 1 ? "venda" : "vendas"}).
        </p>
      )}

      <Card>
        <CardContent className="space-y-3 p-4">
          <p className="text-xs text-muted-foreground">No período</p>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <Tally label="Vendido a prazo" value={money(period.total)} />
            <Tally label="Do faturamento" value={`${Math.round(period.share * 100)}%`} />
            <Tally label="Recebido" value={money(period.received.total)} />
            <Tally
              label="Pagos com atraso"
              value={period.receivedLate}
              alert={period.receivedLate > 0}
            />
          </div>
        </CardContent>
      </Card>

      {overdueOrders.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <AlertTriangle className="size-4 text-warning-foreground" />
              Quem cobrar primeiro
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {overdueOrders.map((order) => (
              <Link
                key={order.id}
                href={`/pedidos/${order.id}`}
                className="flex items-center justify-between gap-3 rounded-lg border border-border px-3 py-2"
              >
                <span className="min-w-0">
                  <span className="block truncate text-sm font-medium">
                    {order.customerName ?? `Pedido ${order.code}`}
                  </span>
                  <span className="block text-xs text-muted-foreground">
                    {money(order.total)} · venceu {dateLabel(order.paymentDueOn)}
                  </span>
                </span>
                <Badge variant="warning">
                  {order.daysLate} {order.daysLate === 1 ? "dia" : "dias"}
                </Badge>
              </Link>
            ))}
          </CardContent>
        </Card>
      )}

      {schedule.length > 0 && (
        <ChartCard
          title="Quando o dinheiro entra"
          hint="O que está em aberto, pelo mês do vencimento."
        >
          <RankingChart
            data={schedule.map((month) => ({ name: monthLabel(month.month), value: month.total }))}
            unit="A receber"
          />
          <ChartTable
            columns={["Mês", "Vendas", "A receber"]}
            rows={schedule.map((month) => [
              monthLabel(month.month),
              month.orders,
              money(month.total),
            ])}
          />
        </ChartCard>
      )}
    </>
  );
};

const Hours: React.FC = () => {
  const hours = useCategory<HourAnalytics[]>("hours");
  if (!hours) return null;

  if (hours.every((slot) => slot.orders === 0)) {
    return <Empty>Nenhum pedido neste período.</Empty>;
  }

  return (
    <ChartCard title="Movimento por hora" hint="Pedidos registrados em cada hora do dia.">
      <HourlyChart data={hours} />
    </ChartCard>
  );
};

const Products: React.FC<{ costs: boolean }> = ({ costs }) => {
  const products = useCategory<ProductAnalytics[]>("products");
  if (!products) return null;

  if (products.length === 0) {
    return <Empty>Nenhum produto vendido neste período.</Empty>;
  }

  return (
    <ChartCard title="O que mais vendeu" hint="Faturamento por produto no período.">
      <RankingChart
        data={products.map((product) => ({ name: product.name, value: product.revenue }))}
        unit="Faturamento"
      />
      <ChartTable
        columns={costs ? ["Produto", "Peso", "Vendas", "Lucro"] : ["Produto", "Peso", "Vendas"]}
        rows={products.map((product) =>
          costs
            ? [
                product.name,
                weight(product.grams),
                money(product.revenue),
                money(product.profit ?? 0),
              ]
            : [product.name, weight(product.grams), money(product.revenue)],
        )}
      />
    </ChartCard>
  );
};

const Team: React.FC = () => {
  const team = useCategory<TeamAnalytics[]>("team");
  if (!team) return null;

  if (team.length === 0) {
    return <Empty>Nenhuma venda registrada neste período.</Empty>;
  }

  return (
    <ChartCard title="Quem registrou" hint="Faturamento por pessoa do balcão.">
      <RankingChart
        data={team.map((person) => ({ name: person.name, value: person.revenue }))}
        unit="Faturamento"
      />
      <ChartTable
        columns={["Pessoa", "Pedidos", "Vendas"]}
        rows={team.map((person) => [person.name, person.orders, money(person.revenue)])}
      />
    </ChartCard>
  );
};

const Delivery: React.FC = () => {
  const delivery = useCategory<DeliveryAnalytics>("delivery");
  if (!delivery) return null;

  const { now, summary, drivers } = delivery;

  return (
    <Card>
      <CardContent className="space-y-3 p-4">
        {/* O que está na rua agora não é do período: pedido de ontem que não
            chegou continua sendo problema hoje. */}
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 rounded-lg border border-border bg-muted/50 p-3 text-xs">
          <Link href="/pedidos?entrega=pendentes" className="underline underline-offset-4">
            {now.toDeliver} na rua agora
          </Link>
          <span className="text-muted-foreground">
            {now.deliveredToday} {now.deliveredToday === 1 ? "entregue" : "entregues"} hoje
          </span>
        </div>

        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <Tally label="A entregar" value={summary.pending} alert={summary.unassigned > 0} />
          <Tally label="A caminho" value={summary.outForDelivery} />
          <Tally label="Entregues" value={summary.delivered} />
          <Tally
            label="Tempo médio"
            value={summary.averageMinutes === null ? "—" : `${summary.averageMinutes} min`}
          />
        </div>

        {summary.unassigned > 0 && (
          <p className="rounded-lg border border-warning/30 bg-warning/10 p-3 text-xs text-warning-foreground">
            {summary.unassigned}{" "}
            {summary.unassigned === 1 ? "pedido pronto sem" : "pedidos prontos sem"} entregador
            definido.
          </p>
        )}

        {summary.pickup > 0 && (
          <p className="text-xs text-muted-foreground">
            {summary.pickup} {summary.pickup === 1 ? "retirada" : "retiradas"} no balcão, fora da
            fila de entrega.
          </p>
        )}

        {drivers.length > 0 && (
          <div className="border-t border-border pt-3">
            <p className="pb-2 text-xs text-muted-foreground">Entregas por entregador</p>
            <RankingChart
              data={drivers.map((driver) => ({ name: driver.name, value: driver.delivered }))}
              format={(value) => String(value)}
              unit="Entregues"
            />
            <ChartTable
              columns={["Entregador", "Recebidos", "Entregues", "Tempo médio"]}
              rows={drivers.map((driver) => [
                driver.name,
                driver.assigned,
                driver.delivered,
                driver.averageMinutes === null ? "—" : `${driver.averageMinutes} min`,
              ])}
            />
          </div>
        )}
      </CardContent>
    </Card>
  );
};

const Stock: React.FC = () => {
  const stock = useCategory<StockAnalytics>("stock");
  if (!stock) return null;

  return (
    <>
      <div className="grid grid-cols-2 gap-3">
        <Stat
          to="/produtos"
          label="Produtos ativos"
          value={String(stock.active)}
          hint={stock.low > 0 ? `${stock.low} abaixo do mínimo` : "estoque em dia"}
          alert={stock.low > 0}
        />
        {stock.value !== undefined && (
          <Stat
            label="Parado em estoque"
            value={money(stock.value)}
            hint="custo do que ainda há"
          />
        )}
      </div>

      {stock.lowProducts.length > 0 && (
        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2 text-sm">
              <AlertTriangle className="size-4 text-warning-foreground" />
              Estoque baixo
            </CardTitle>
            <Link href="/produtos" className="text-xs font-medium underline underline-offset-4">
              ver estoque
            </Link>
          </CardHeader>
          <CardContent className="space-y-2">
            {stock.lowProducts.map((product) => (
              <Link
                key={product.id}
                href={`/produtos/${product.id}`}
                className="flex items-center justify-between gap-3 rounded-lg border border-border px-3 py-2"
              >
                <span className="truncate text-sm font-medium">{product.name}</span>
                <Badge variant="warning">{weight(product.stockGrams)}</Badge>
              </Link>
            ))}
          </CardContent>
        </Card>
      )}

      {stock.topValue && stock.topValue.length > 0 && (
        <ChartCard
          title="Onde o dinheiro está parado"
          hint="Custo do que ainda há em estoque, por produto."
        >
          <RankingChart data={stock.topValue} color={SERIES.warning} unit="Custo em estoque" />
        </ChartCard>
      )}
    </>
  );
};

/**
 * O mapa dos pedidos.
 *
 * Só entra pedido com coordenada: retirada no balcão não tem endereço, e
 * endereço que a busca não achou não tem ponto. O vazio explica isso — um
 * mapa em branco pareceria defeito.
 */
const Mapa: React.FC = () => {
  const orders = useCategory<Order[]>("map");
  if (!orders) return null;

  if (orders.length === 0) {
    return (
      <Empty>
        Nenhum pedido com endereço no mapa nesse período. Retirada no balcão e
        endereço que a busca não encontrou não viram ponto.
      </Empty>
    );
  }

  return <OrdersMap orders={orders} />;
};

const Recent: React.FC = () => {
  const orders = useCategory<Order[]>("recent");
  if (!orders) return null;

  if (orders.length === 0) {
    return <Empty>Nenhum pedido nesse período.</Empty>;
  }

  return (
    <Card>
      <CardContent className="p-4">
        <ul className="divide-y divide-border">
          {orders.map((order) => (
            <li key={order.id}>
              <Link
                href={`/pedidos/${order.id}`}
                className="flex items-center justify-between gap-3 py-3"
              >
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">
                    {order.customerName ?? `Pedido ${order.code}`}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {dateTimeLabel(order.insertedAt)}
                    {order.userName ? ` · ${order.userName}` : ""}
                  </p>
                </div>
                <div className="flex shrink-0 flex-col items-end gap-1">
                  <p className="text-sm font-semibold tabular-nums">{money(order.total)}</p>
                  {order.status === "cancelled" ? (
                    <Badge variant="destructive">cancelado</Badge>
                  ) : (
                    <DeliveryBadge order={order} />
                  )}
                </div>
              </Link>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
};

/** Número seco de um recorte — o gráfico ao lado explica, este só conta. */
const Tally: React.FC<{ label: string; value: number | string; alert?: boolean }> = ({
  label,
  value,
  alert,
}) => (
  <div className="rounded-lg border border-border p-3">
    <p className={cn("text-lg font-semibold tabular-nums", alert && "text-warning-foreground")}>
      {value}
    </p>
    <p className="text-[11px] text-muted-foreground">{label}</p>
  </div>
);

const Stat: React.FC<{
  label: string;
  value: string;
  hint: string;
  to?: string;
  alert?: boolean;
  icon?: React.ComponentType<{ className?: string }>;
}> = ({ label, value, hint, to, alert, icon: Icon }) => {
  const body = (
    <Card className={cn(to && "transition-colors active:bg-accent")}>
      <CardContent className="flex items-start justify-between gap-3 p-4">
        <div className="min-w-0">
          <p className="text-xs text-muted-foreground">{label}</p>
          <p className="mt-1 text-xl font-semibold tabular-nums">{value}</p>
          <p
            className={cn(
              "mt-1 text-xs leading-snug",
              alert ? "text-warning-foreground" : "text-muted-foreground",
            )}
          >
            {hint}
          </p>
        </div>
        {Icon && <Icon className="size-5 shrink-0 text-muted-foreground" />}
      </CardContent>
    </Card>
  );

  return to ? <Link href={to}>{body}</Link> : body;
};

const Empty: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <Card>
    <CardContent className="py-8 text-center text-sm text-muted-foreground">{children}</CardContent>
  </Card>
);

const dayLabel = (iso: string) => {
  const [, month, day] = iso.split("-");
  return `${day}/${month}`;
};
