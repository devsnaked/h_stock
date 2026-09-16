import * as React from "react";
import { Link, useForm } from "@inertiajs/react";
import { Bike, CheckCheck, MapPin, Navigation, Package } from "lucide-react";
import { AppLayout } from "@/layouts/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { DeliveryBadge } from "@/components/DeliveryBadge";
import { OrdersMap } from "@/components/OrdersMap";
import { dateTimeLabel, money, weight } from "@/lib/format";
import type { Order } from "@/types";

type Props = {
  /** O que está na mão do entregador agora: a entregar e a caminho. */
  orders: Order[];
  deliveredToday: number;
};

/**
 * O app do entregador.
 *
 * Uma lista, dois botões por cartão, nada mais: quem abre esta tela está na
 * rua, muitas vezes de capacete na mão. O endereço e a rota vêm antes do
 * dinheiro, porque a pergunta do momento é "para onde vou agora?" — o total
 * aparece porque em muita entrega ainda se recebe na porta.
 */
export default function Deliveries({ orders, deliveredToday }: Props) {
  const onTheWay = orders.filter((order) => order.deliveryStatus === "out_for_delivery");
  const waiting = orders.filter((order) => order.deliveryStatus === "pending");

  // Endereço sem coordenada não vira ponto — o cartão continua mostrando o
  // texto, que é o que dá para seguir.
  const located = orders.filter(
    (order) => order.deliveryLat !== null && order.deliveryLon !== null,
  );

  return (
    <AppLayout
      title="Minhas entregas"
      subtitle={
        orders.length === 0
          ? "nada na sua mão agora"
          : `${orders.length} ${orders.length === 1 ? "pedido" : "pedidos"} com você`
      }
    >
      <div className="space-y-4">
        <div className="grid grid-cols-3 gap-2">
          <Tally label="A sair" value={waiting.length} icon={Package} />
          <Tally label="A caminho" value={onTheWay.length} icon={Bike} />
          <Tally label="Entregues hoje" value={deliveredToday} icon={CheckCheck} />
        </div>

        {/* Onde é cada uma, antes da lista: a primeira pergunta de quem abre
            esta tela é para que lado sair. O balão de cada ponto tem o
            cliente, o valor e a rota. */}
        {located.length > 0 && <OrdersMap orders={located} route />}

        {orders.length === 0 ? (
          <Card>
            <CardContent className="space-y-1 p-8 text-center">
              <p className="text-sm font-medium">Nenhuma entrega agora</p>
              <p className="text-sm text-muted-foreground">
                Quando o balcão mandar um pedido para você, ele aparece aqui.
              </p>
            </CardContent>
          </Card>
        ) : (
          <ul className="space-y-3">
            {[...onTheWay, ...waiting].map((order) => (
              <li key={order.id}>
                <DeliveryCard order={order} />
              </li>
            ))}
          </ul>
        )}
      </div>
    </AppLayout>
  );
}

const Tally: React.FC<{
  label: string;
  value: number;
  icon: React.ComponentType<{ className?: string }>;
}> = ({ label, value, icon: Icon }) => (
  <div className="rounded-xl border border-border bg-card p-3">
    <Icon className="size-4 text-muted-foreground" />
    <p className="pt-1 text-2xl font-semibold tabular-nums leading-none">{value}</p>
    <p className="pt-1 text-[11px] text-muted-foreground">{label}</p>
  </div>
);

const DeliveryCard: React.FC<{ order: Order }> = ({ order }) => {
  const { post, processing } = useForm({});
  const advance = (stage: string) => post(`/pedidos/${order.id}/entrega/${stage}`);

  const located = order.deliveryLat !== null && order.deliveryLon !== null;

  return (
    <Card>
      <CardContent className="space-y-3 p-4">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-sm font-semibold">
              {order.customerName ?? `Pedido ${order.code}`}
            </p>
            <p className="text-xs text-muted-foreground">
              {order.code} · {dateTimeLabel(order.insertedAt)}
            </p>
          </div>
          <DeliveryBadge order={order} />
        </div>

        {order.deliveryAddress ? (
          <div className="flex items-start gap-2">
            <MapPin className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
            <p className="min-w-0 flex-1 text-sm">{order.deliveryAddress}</p>
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">
            Sem endereço no pedido — confirme no balcão.
          </p>
        )}

        {/* O que vai na sacola, para conferir antes de sair. */}
        {order.items && order.items.length > 0 && (
          <ul className="space-y-0.5 text-xs text-muted-foreground">
            {order.items.map((item) => (
              <li key={item.id}>
                {weight(item.grams)} de {item.productName}
              </li>
            ))}
          </ul>
        )}

        <div className="flex items-center justify-between gap-3 border-t border-border pt-3">
          <span className="text-xs text-muted-foreground">A receber</span>
          <Badge variant="outline" className="tabular-nums">
            {money(order.total)}
          </Badge>
        </div>

        <div className="grid gap-2">
          {located && (
            <Button asChild variant="outline" size="sm">
              <a
                href={`https://www.google.com/maps/dir/?api=1&destination=${order.deliveryLat},${order.deliveryLon}`}
                target="_blank"
                rel="noreferrer"
              >
                <Navigation className="size-4" />
                Traçar rota
              </a>
            </Button>
          )}

          {order.deliveryStatus === "pending" ? (
            <Button size="lg" disabled={processing} onClick={() => advance("saiu")}>
              Saí para entrega
            </Button>
          ) : (
            <Button size="lg" disabled={processing} onClick={() => advance("entregue")}>
              Entreguei
            </Button>
          )}

          <Button asChild variant="ghost" size="sm" className="text-muted-foreground">
            <Link href={`/pedidos/${order.id}`}>Ver o pedido</Link>
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};
