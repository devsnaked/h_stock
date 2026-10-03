import * as React from "react";
import { Link, router, usePage } from "@inertiajs/react";
import {
  ArrowDownLeft,
  ArrowUpRight,
  Ban,
  Bike,
  CheckCheck,
  Coins,
  HandCoins,
  PackagePlus,
  Pencil,
  Receipt,
  RotateCcw,
  ScrollText,
  Search,
  SlidersHorizontal,
  Undo2,
  X,
} from "lucide-react";
import { AppLayout } from "@/layouts/AppLayout";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Pagination, type Page } from "@/components/Pagination";
import { cn } from "@/lib/utils";
import { dateTimeLabel } from "@/lib/format";
import type { AuditAction, AuditEntry } from "@/types";

type Props = {
  entries: AuditEntry[];
  filter: string;
  /** Id de quem filtra a lista, devolvido pelo servidor. */
  author: string;
  search: string;
  /** Quem já apareceu no log — só quem agiu entra no seletor. */
  authors: { id: string; name: string }[];
  page: Page;
};

const FILTERS = [
  { id: "todos", label: "Tudo" },
  { id: "estoque", label: "Estoque" },
  { id: "pedidos", label: "Pedidos" },
  { id: "produtos", label: "Produtos" },
];

/**
 * Cada ação tem ícone e cor próprios: numa lista cronológica longa é a cor
 * que deixa varrer a coluna procurando o que interessa, sem ler frase por
 * frase. Verde entra mercadoria ou dinheiro, âmbar sai, vermelho desfaz.
 */
const LOOK: Record<
  AuditAction,
  { icon: React.ComponentType<{ className?: string }>; tone: string; label: string }
> = {
  stock_in: { icon: PackagePlus, tone: "text-emerald-600 dark:text-emerald-400", label: "Entrada" },
  stock_out: { icon: ArrowUpRight, tone: "text-amber-600 dark:text-amber-400", label: "Saída" },
  stock_return: {
    icon: ArrowDownLeft,
    tone: "text-emerald-600 dark:text-emerald-400",
    label: "Devolução",
  },
  stock_adjusted: {
    icon: SlidersHorizontal,
    tone: "text-amber-600 dark:text-amber-400",
    label: "Ajuste",
  },
  stock_cost_corrected: {
    icon: Coins,
    tone: "text-amber-600 dark:text-amber-400",
    label: "Custo corrigido",
  },
  product_created: {
    icon: PackagePlus,
    tone: "text-muted-foreground",
    label: "Produto cadastrado",
  },
  product_updated: { icon: Pencil, tone: "text-muted-foreground", label: "Produto alterado" },
  order_registered: {
    icon: Receipt,
    tone: "text-emerald-600 dark:text-emerald-400",
    label: "Venda",
  },
  order_cancelled: {
    icon: Ban,
    tone: "text-destructive",
    label: "Cancelamento",
  },
  order_driver_assigned: { icon: Bike, tone: "text-muted-foreground", label: "Despacho" },
  order_out_for_delivery: { icon: Bike, tone: "text-muted-foreground", label: "Saiu" },
  order_delivered: {
    icon: CheckCheck,
    tone: "text-emerald-600 dark:text-emerald-400",
    label: "Entregue",
  },
  order_reopened: { icon: Undo2, tone: "text-amber-600 dark:text-amber-400", label: "Reaberto" },
  order_paid: {
    icon: HandCoins,
    tone: "text-emerald-600 dark:text-emerald-400",
    label: "Pago",
  },
  order_updated: { icon: Pencil, tone: "text-muted-foreground", label: "Pedido editado" },
};

export default function AuditIndex({
  entries,
  filter,
  author,
  search,
  authors,
  page,
}: Props) {
  const { url } = usePage();

  // Mesmo contrato da lista de pedidos: o recorte inteiro mora na URL, então
  // voltar pelo histórico e compartilhar o link funcionam.
  const navigate = (changes: Record<string, string | null>) => {
    const params = new URLSearchParams(url.split("?")[1] ?? "");

    for (const [key, value] of Object.entries(changes)) {
      if (value === null || value === "") params.delete(key);
      else params.set(key, value);
    }

    router.get("/auditoria", Object.fromEntries(params), {
      preserveState: true,
      preserveScroll: true,
      replace: true,
    });
  };

  const filtering = search !== "" || author !== "" || filter !== "todos";

  return (
    <AppLayout title="Auditoria" subtitle="Tudo que mexeu no estoque e nos pedidos">
      <div className="space-y-4">
        <div className="flex items-center gap-2 overflow-x-auto pb-1">
          {FILTERS.map((option) => (
            <button
              key={option.id}
              type="button"
              onClick={() => navigate({ tipo: option.id === "todos" ? null : option.id, pagina: null })}
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
        </div>

        <div className="flex flex-col gap-2 sm:flex-row">
          <div className="flex-1">
            <SearchField
              value={search}
              onSearch={(term) => navigate({ busca: term || null, pagina: null })}
            />
          </div>

          {/* "Quem" é a segunda pergunta do administrador, sempre. Um select
              nativo: no celular ele abre a roda do sistema, que é mais rápida
              de girar do que qualquer lista desenhada por nós. */}
          <select
            aria-label="Filtrar por quem fez"
            value={author}
            onChange={(event) => navigate({ quem: event.target.value || null, pagina: null })}
            className="h-10 shrink-0 rounded-md border border-border bg-card px-3 text-sm sm:w-52"
          >
            <option value="">Qualquer pessoa</option>
            {authors.map((person) => (
              <option key={person.id} value={person.id}>
                {person.name}
              </option>
            ))}
          </select>
        </div>

        {entries.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
              <ScrollText className="size-8 text-muted-foreground/60" />
              <p className="text-sm text-muted-foreground">
                {filtering
                  ? "Nada encontrado com esse recorte."
                  : "Nada registrado ainda. O log começa na primeira movimentação."}
              </p>
            </CardContent>
          </Card>
        ) : (
          <ul className="space-y-2">
            {entries.map((entry) => (
              <li key={entry.id}>
                <Row entry={entry} />
              </li>
            ))}
          </ul>
        )}

        <Pagination
          page={page}
          label="registro"
          onPage={(number) => navigate({ pagina: String(number) })}
        />
      </div>
    </AppLayout>
  );
}

/**
 * Uma linha do log.
 *
 * Vira link quando dá para abrir o que ela descreve — o produto ou o pedido.
 * Produto cadastrado e depois removido da tela não deixa a linha quebrada: o
 * rótulo está congelado nela, e o link é o extra.
 */
const Row: React.FC<{ entry: AuditEntry }> = ({ entry }) => {
  const look = LOOK[entry.action];
  const Icon = look.icon;

  const body = (
    <Card className="transition-colors active:bg-accent">
      <CardContent className="flex items-start gap-3 p-4">
        <Icon className={cn("mt-0.5 size-5 shrink-0", look.tone)} />

        <div className="min-w-0 flex-1 space-y-1">
          <div className="flex flex-wrap items-baseline gap-x-2">
            <span className={cn("text-sm font-medium", look.tone)}>{look.label}</span>
            <span className="truncate text-sm text-foreground">{entry.subjectLabel}</span>
          </div>

          <p className="text-sm text-muted-foreground">{entry.summary}</p>

          <p className="text-xs text-muted-foreground">
            {entry.userName ?? "sistema"} · {dateTimeLabel(entry.insertedAt)}
          </p>
        </div>
      </CardContent>
    </Card>
  );

  const href =
    entry.subjectType === "order"
      ? `/pedidos/${entry.subjectId}`
      : `/produtos/${entry.subjectId}`;

  return <Link href={href}>{body}</Link>;
};

/** Mesma busca com pausa da lista de pedidos: uma requisição por letra não. */
const SearchField: React.FC<{ value: string; onSearch: (term: string) => void }> = ({
  value,
  onSearch,
}) => {
  const [term, setTerm] = React.useState(value);

  React.useEffect(() => setTerm(value), [value]);

  React.useEffect(() => {
    if (term === value) return;

    const timer = setTimeout(() => onSearch(term.trim()), 350);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [term, value]);

  return (
    <div className="relative">
      <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />

      <Input
        type="search"
        inputMode="search"
        aria-label="Buscar no log"
        placeholder="Produto, código do pedido, o que foi feito..."
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
