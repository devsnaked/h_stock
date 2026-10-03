import * as React from "react";
import { Link, router, usePage } from "@inertiajs/react";
import { Plus, Receipt, Search, X } from "lucide-react";
import { AppLayout } from "@/layouts/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { DeliveryBadge } from "@/components/DeliveryBadge";
import { PaymentBadge } from "@/components/PaymentBadge";
import { Pagination, type Page } from "@/components/Pagination";
import { cn } from "@/lib/utils";
import { dateLabel, dateTimeLabel, money } from "@/lib/format";
import type { Order } from "@/types";

type Props = {
  orders: Order[];
  filter: string;
  /** Só vendas a prazo ainda não pagas — combina com o filtro de entrega. */
  unpaid: boolean;
  /** O termo em vigor, devolvido pelo servidor — a busca mora na URL. */
  search: string;
  /** Quem alcança os pedidos da equipe inteira vê de quem é cada um. */
  managesOrders: boolean;
  page: Page;
};

const FILTERS = [
  { id: "todos", label: "Todos" },
  { id: "pendentes", label: "A entregar" },
  { id: "caminho", label: "A caminho" },
  { id: "entregues", label: "Entregues" },
];

export default function OrdersIndex({
  orders,
  filter,
  unpaid,
  search,
  managesOrders,
  page,
}: Props) {
  const { url } = usePage();

  /**
   * A lista inteira mora na URL: filtro, busca, período e página. Assim o
   * botão de voltar funciona, o link é compartilhável e recarregar não perde
   * o que a pessoa estava vendo.
   *
   * `preserveState` mantém o componente vivo — sem isso o campo de busca
   * perderia o foco a cada tecla.
   */
  const navigate = (changes: Record<string, string | null>) => {
    const params = new URLSearchParams(url.split("?")[1] ?? "");

    for (const [key, value] of Object.entries(changes)) {
      if (value === null || value === "") params.delete(key);
      else params.set(key, value);
    }

    router.get("/pedidos", Object.fromEntries(params), {
      preserveState: true,
      preserveScroll: true,
      replace: true,
    });
  };

  // Trocar filtro ou busca volta para a primeira página: continuar na página
  // 4 de um resultado que agora tem duas seria uma tela vazia.
  const apply = (id: string) =>
    navigate({ entrega: id === "todos" ? null : id, pagina: null });

  return (
    <AppLayout
      title="Pedidos"
      subtitle={managesOrders ? "Todos os pedidos da loja" : "Os pedidos que você registrou"}
    >
      <div className="space-y-4">
        {/* Filtros à esquerda, registrar à direita: as duas coisas que se faz
            ao abrir a tela ficam na mesma linha. Os filtros rolam na
            horizontal quando não cabem; o botão não sai do lugar. */}
        <div className="flex items-center gap-2">
          <div className="flex flex-1 items-center gap-2 overflow-x-auto pb-1">
            {FILTERS.map((option) => (
              <button
                key={option.id}
                type="button"
                onClick={() => apply(option.id)}
                aria-pressed={filter === option.id}
                className={cn(
                  "h-9 shrink-0 rounded-full border px-3.5 text-sm font-medium transition-colors",
                  filter === option.id
                    ? "border-transparent bg-primary text-primary-foreground"
                    : "border-border bg-card text-muted-foreground",
                )}
              >
                {option.label}
              </button>
            ))}

            {/* Pagamento é outra pergunta que a entrega, e por isso um
                interruptor à parte: "a entregar e não pagos" é uma lista
                válida. Separado dos outros por um traço para não parecer mais
                uma opção do mesmo grupo. */}
            <span aria-hidden className="h-5 w-px shrink-0 bg-border" />
            <button
              type="button"
              onClick={() => navigate({ pagamento: unpaid ? null : "pendente", pagina: null })}
              aria-pressed={unpaid}
              className={cn(
                "h-9 shrink-0 rounded-full border px-3.5 text-sm font-medium transition-colors",
                unpaid
                  ? "border-transparent bg-primary text-primary-foreground"
                  : "border-border bg-card text-muted-foreground",
              )}
            >
              Não pagos
            </button>
          </div>

          <Button asChild size="sm" className="shrink-0">
            <Link href="/pedidos/novo">
              <Plus className="size-4" />
              <span>
                Novo<span className="hidden sm:inline"> pedido</span>
              </span>
            </Link>
          </Button>
        </div>

        <SearchField
          value={search}
          onSearch={(term) => navigate({ busca: term || null, pagina: null })}
        />

        {orders.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
              <Receipt className="size-8 text-muted-foreground/60" />
              <p className="text-sm text-muted-foreground">
                {search !== ""
                  ? `Nada encontrado para "${search}".`
                  : unpaid
                    ? "Nenhuma venda a prazo em aberto."
                    : filter === "todos"
                      ? "Nenhum pedido registrado."
                      : "Nenhum pedido nesta situação."}
              </p>
            </CardContent>
          </Card>
        ) : (
          <ul className="space-y-2">
            {orders.map((order) => (
              <li key={order.id}>
                <Link href={`/pedidos/${order.id}`}>
                  <Card className="transition-colors active:bg-accent">
                    <CardContent className="flex items-center justify-between gap-3 p-4">
                      <div className="min-w-0 space-y-1">
                        <p className="truncate font-medium">
                          {order.customerName ?? `Pedido ${order.code}`}
                        </p>
                        <p className="text-xs text-muted-foreground">
                          {dateTimeLabel(order.insertedAt)}
                          {order.itemsCount
                            ? ` · ${order.itemsCount} ${order.itemsCount === 1 ? "item" : "itens"}`
                            : ""}
                          {managesOrders && order.userName ? ` · ${order.userName}` : ""}
                        </p>

                        {/* Para quem foi mandado: é a pergunta do balcão
                            quando o cliente liga perguntando da entrega. */}
                        {order.driverName && order.deliveryStatus !== "delivered" && (
                          <p className="truncate text-xs text-muted-foreground">
                            com {order.driverName}
                          </p>
                        )}

                        {/* Na lista de cobrança, o vencimento é a primeira
                            coisa que se procura. */}
                        {order.status === "completed" &&
                          order.paymentDueOn &&
                          order.paidAt === null && (
                            <p
                              className={cn(
                                "text-xs",
                                order.paymentOverdue
                                  ? "font-medium text-warning-foreground"
                                  : "text-muted-foreground",
                              )}
                            >
                              vence {dateLabel(order.paymentDueOn)}
                            </p>
                          )}
                      </div>

                      <div className="flex shrink-0 flex-col items-end gap-1">
                        <span
                          className={cn(
                            "text-sm font-semibold tabular-nums",
                            order.status === "cancelled" &&
                              "text-muted-foreground line-through",
                          )}
                        >
                          {money(order.total)}
                        </span>
                        {order.status === "cancelled" ? (
                          <Badge variant="destructive">cancelado</Badge>
                        ) : (
                          <div className="flex flex-wrap justify-end gap-1">
                            <PaymentBadge order={order} />
                            <DeliveryBadge order={order} />
                          </div>
                        )}
                      </div>
                    </CardContent>
                  </Card>
                </Link>
              </li>
            ))}
          </ul>
        )}

        <Pagination
          page={page}
          label="pedido"
          onPage={(number) => navigate({ pagina: String(number) })}
        />
      </div>
    </AppLayout>
  );
}

/**
 * Busca da lista.
 *
 * O que a pessoa digita fica no estado local e vai para a URL depois de uma
 * pausa de 350ms: no celular, buscar a cada tecla seria uma requisição por
 * letra. Enter manda na hora, para quem já sabe o que quer.
 */
const SearchField: React.FC<{ value: string; onSearch: (term: string) => void }> = ({
  value,
  onSearch,
}) => {
  const [term, setTerm] = React.useState(value);

  // O servidor é quem manda: voltar pelo histórico ou limpar o filtro tem de
  // aparecer no campo.
  React.useEffect(() => setTerm(value), [value]);

  React.useEffect(() => {
    if (term === value) return;

    const timer = setTimeout(() => onSearch(term.trim()), 350);
    return () => clearTimeout(timer);
    // `onSearch` muda a cada render (fecha sobre a URL atual); incluí-la aqui
    // reiniciaria o timer sem parar.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [term, value]);

  return (
    <div className="relative">
      <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />

      <Input
        type="search"
        inputMode="search"
        aria-label="Buscar pedidos"
        placeholder="Cliente, endereço, código, entregador..."
        className="px-9"
        value={term}
        onChange={(event) => setTerm(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.preventDefault();
            onSearch(term.trim());
          }
        }}
      />

      {term !== "" && (
        <button
          type="button"
          aria-label="Limpar busca"
          onClick={() => {
            setTerm("");
            onSearch("");
          }}
          className="absolute right-2 top-1/2 -translate-y-1/2 rounded-md p-1.5 text-muted-foreground hover:text-foreground"
        >
          <X className="size-4" />
        </button>
      )}
    </div>
  );
};
