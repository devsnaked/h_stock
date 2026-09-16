import * as React from "react";
import L from "leaflet";
import { deliveryLabel } from "@/components/DeliveryBadge";
import { dateTimeLabel, money } from "@/lib/format";
import { cn } from "@/lib/utils";
import type { Order } from "@/types";

type Props = {
  orders: Order[];
  /**
   * Põe "traçar rota" no balão. É para a tela do entregador: ali o mapa não
   * serve para olhar a loja, e sim para sair de moto.
   */
  route?: boolean;
  className?: string;
};

/** Um ponto do mapa: a coordenada e todos os pedidos que saíram dela. */
type Point = {
  lat: number;
  lon: number;
  address: string | null;
  orders: Order[];
};

/**
 * O que a cor do ponto diz. Segue a régua do resto do sistema: âmbar é o que
 * ainda pede ação, cinza é o que saiu de cena.
 */
const COLORS = {
  street: "#f59e0b",
  done: "#059669",
  cancelled: "#94a3b8",
} as const;

const LEGEND = [
  ["street", "a entregar"],
  ["done", "entregue ou retirado"],
  ["cancelled", "cancelado"],
] as const;

/**
 * O mapa dos pedidos do período: um pino por endereço, o balão com os pedidos
 * daquele endereço.
 *
 * **Endereço repetido é um pino só.** O cliente que pede toda semana moraria
 * embaixo de uma pilha de pinos sobrepostos, e o de cima esconderia os
 * outros; agrupando, o balão lista os pedidos e o número no pino diz quantos
 * são.
 *
 * Leaflet com tiles do OpenStreetMap, como no mapa do endereço
 * (`AddressMap`): sem chave de API e sem script de terceiro na página. O
 * ponto é `circleMarker` (SVG) pelo mesmo motivo de lá — o pino padrão é um
 * PNG que o Leaflet monta por caminho relativo, e num bundle com hash esse
 * caminho não existe.
 */
export const OrdersMap: React.FC<Props> = ({ orders, route = false, className }) => {
  const container = React.useRef<HTMLDivElement | null>(null);
  const map = React.useRef<L.Map | null>(null);
  const layer = React.useRef<L.LayerGroup | null>(null);

  const points = React.useMemo(() => group(orders), [orders]);

  React.useEffect(() => {
    if (!container.current || map.current) return;

    const instance = L.map(container.current, {
      // O enquadramento vem dos pontos, no efeito abaixo.
      center: [-14.235, -51.925],
      zoom: 4,
      scrollWheelZoom: false,
      zoomControl: true,
    });

    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: "© OpenStreetMap",
    }).addTo(instance);

    layer.current = L.layerGroup().addTo(instance);
    map.current = instance;

    // O bloco do painel monta este mapa junto com o dado que acabou de
    // chegar; se o container ainda não tiver altura no primeiro quadro, o
    // Leaflet desenha um retângulo cinza e fica assim. Uma medição a mais
    // resolve.
    requestAnimationFrame(() => instance.invalidateSize());

    return () => {
      instance.remove();
      map.current = null;
      layer.current = null;
    };
  }, []);

  React.useEffect(() => {
    const instance = map.current;
    const group = layer.current;
    if (!instance || !group) return;

    group.clearLayers();

    for (const point of points) {
      L.circleMarker([point.lat, point.lon], {
        radius: point.orders.length > 1 ? 11 : 8,
        weight: 3,
        color: color(point),
        fillColor: color(point),
        fillOpacity: 0.35,
      })
        .bindTooltip(tooltip(point), { direction: "top" })
        .bindPopup(popup(point, route), { maxWidth: 280 })
        .addTo(group);
    }

    if (points.length > 0) {
      instance.fitBounds(
        L.latLngBounds(points.map((point) => [point.lat, point.lon] as [number, number])),
        // Um ponto só não tem área: sem o teto de zoom o mapa colaria na
        // calçada, e ninguém reconhece o bairro assim.
        { padding: [24, 24], maxZoom: 16 },
      );
    }
  }, [points, route]);

  return (
    <div className="space-y-2">
      <div
        ref={container}
        aria-label={`Mapa com ${orders.length} pedido(s) em ${points.length} endereço(s)`}
        className={cn(
          "h-72 w-full overflow-hidden rounded-xl border border-border",
          className,
        )}
      />

      <ul className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
        {/* Só as cores que estão no mapa: legenda de estado que não existe
            ali é ruído — na tela do entregador, por exemplo, nada é
            cancelado. */}
        {LEGEND.filter(([key]) => points.some((point) => color(point) === COLORS[key])).map(([key, label]) => (
          <li key={key} className="flex items-center gap-1.5">
            <span
              aria-hidden
              className="size-2.5 rounded-full"
              style={{ backgroundColor: COLORS[key] }}
            />
            {label}
          </li>
        ))}
      </ul>
    </div>
  );
};

/** Pedidos do mesmo ponto viram um pino só. */
function group(orders: Order[]): Point[] {
  const points = new Map<string, Point>();

  for (const order of orders) {
    if (order.deliveryLat === null || order.deliveryLon === null) continue;

    // A chave é a coordenada arredondada: o mesmo endereço buscado duas vezes
    // volta com a última casa diferente, e dois pinos sobrepostos por causa
    // de um metro não ajudam ninguém.
    const key = `${order.deliveryLat.toFixed(5)},${order.deliveryLon.toFixed(5)}`;
    const existing = points.get(key);

    if (existing) existing.orders.push(order);
    else
      points.set(key, {
        lat: order.deliveryLat,
        lon: order.deliveryLon,
        address: order.deliveryAddress,
        orders: [order],
      });
  }

  return [...points.values()];
}

/** A cor do ponto é a do pedido mais urgente que ele guarda. */
function color(point: Point): string {
  const ativos = point.orders.filter((order) => order.status !== "cancelled");

  if (ativos.length === 0) return COLORS.cancelled;

  const naRua = ativos.some(
    (order) =>
      order.deliveryStatus === "pending" || order.deliveryStatus === "out_for_delivery",
  );

  return naRua ? COLORS.street : COLORS.done;
}

function tooltip(point: Point): string {
  const quantos =
    point.orders.length > 1 ? `${point.orders.length} pedidos` : "1 pedido";

  return escape(point.address ? `${point.address} · ${quantos}` : quantos);
}

/**
 * O balão do ponto, em HTML: o Leaflet monta o popup fora do React.
 *
 * O link é um `<a>` comum, não um `Link` do Inertia — dentro do popup não há
 * árvore React para o Inertia interceptar, e uma navegação inteira até o
 * pedido é aceitável no clique de um pino.
 *
 * Tudo que veio do cliente (nome, endereço) passa por `escape`: é texto que
 * alguém digitou no balcão, e aqui ele estaria virando HTML.
 */
function popup(point: Point, route: boolean): string {
  const linhas = point.orders
    .map((order) => {
      const titulo = order.customerName ?? `Pedido ${order.code}`;
      const estado =
        order.status === "cancelled" ? "cancelado" : deliveryLabel(order.deliveryStatus);

      return `
        <li class="border-t border-border pt-2 first:border-0 first:pt-0">
          <a href="/pedidos/${escape(order.id)}" class="block">
            <span class="flex items-baseline justify-between gap-2">
              <span class="truncate text-sm font-medium underline underline-offset-4">${escape(titulo)}</span>
              <span class="shrink-0 text-sm font-semibold tabular-nums">${escape(money(order.total))}</span>
            </span>
            <span class="block text-xs text-muted-foreground">
              ${escape(dateTimeLabel(order.insertedAt))} · ${escape(estado)}
            </span>
          </a>
        </li>`;
    })
    .join("");

  const endereco = point.address
    ? `<p class="mb-2 text-xs text-muted-foreground">${escape(point.address)}</p>`
    : "";

  const rota = route
    ? `<a
         href="https://www.google.com/maps/dir/?api=1&destination=${point.lat},${point.lon}"
         target="_blank" rel="noreferrer"
         class="mt-2 block border-t border-border pt-2 text-sm font-medium underline underline-offset-4"
       >Traçar rota</a>`
    : "";

  return `<div class="min-w-52">${endereco}<ul class="space-y-2">${linhas}</ul>${rota}</div>`;
}

const ESCAPES: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

const escape = (text: string) => text.replace(/[&<>"']/g, (char) => ESCAPES[char]);
