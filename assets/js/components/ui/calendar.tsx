import * as React from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export type DateRange = { from: string; to: string };

type CalendarProps = {
  /** Intervalo selecionado, em datas ISO (`2026-08-13`). */
  selected: DateRange;
  onSelect: (range: DateRange) => void;
  /** Último dia selecionável — normalmente "hoje" vindo do servidor. */
  max?: string;
  className?: string;
};

const WEEKDAYS = ["D", "S", "T", "Q", "Q", "S", "S"];

const MONTHS = [
  "janeiro",
  "fevereiro",
  "março",
  "abril",
  "maio",
  "junho",
  "julho",
  "agosto",
  "setembro",
  "outubro",
  "novembro",
  "dezembro",
];

/**
 * Calendário de intervalo, escrito no padrão do resto do `ui/`: Tailwind com
 * os tokens do tema, `cn` para compor classe, e nenhuma dependência nova.
 *
 * O `<input type="date">` do navegador foi trocado por isto porque ele é a
 * única peça da interface que o app não desenha: muda de cara em cada
 * sistema, ignora o tema escuro, abre um seletor diferente no iOS e no
 * Android, e não sabe o que é um *intervalo* — que é justamente o que o
 * painel escolhe.
 *
 * As contas de data são feitas com ano/mês/dia soltos, nunca com
 * `toISOString()`: o fuso do aparelho transformaria 1º de agosto às 00h em 31
 * de julho, e o relatório mudaria de mês sozinho.
 */
export const Calendar: React.FC<CalendarProps> = ({ selected, onSelect, max, className }) => {
  const [cursor, setCursor] = React.useState(() => monthOf(selected.to || selected.from));
  // Primeiro toque marca o começo; o segundo fecha o intervalo. Enquanto o
  // segundo não vem, a data sob o dedo mostra como o intervalo ficaria.
  const [anchor, setAnchor] = React.useState<string | null>(null);
  const [hovered, setHovered] = React.useState<string | null>(null);

  const preview: DateRange = anchor
    ? order(anchor, hovered ?? anchor)
    : { from: selected.from, to: selected.to };

  const pick = (day: string) => {
    if (!anchor) {
      setAnchor(day);
      setHovered(day);
      return;
    }

    onSelect(order(anchor, day));
    setAnchor(null);
    setHovered(null);
  };

  const days = grid(cursor);

  return (
    <div className={cn("select-none space-y-3", className)}>
      <div className="flex items-center justify-between gap-2">
        <Button
          variant="ghost"
          size="icon"
          aria-label="Mês anterior"
          onClick={() => setCursor(shiftMonth(cursor, -1))}
        >
          <ChevronLeft className="size-4" />
        </Button>

        <p aria-live="polite" className="text-sm font-medium">
          {MONTHS[cursor.month]} de {cursor.year}
        </p>

        <Button
          variant="ghost"
          size="icon"
          aria-label="Próximo mês"
          disabled={max !== undefined && startOfMonth(cursor) > max}
          onClick={() => setCursor(shiftMonth(cursor, 1))}
        >
          <ChevronRight className="size-4" />
        </Button>
      </div>

      <div className="grid grid-cols-7 gap-y-1 text-center">
        {WEEKDAYS.map((label, index) => (
          <span key={index} className="pb-1 text-xs font-medium text-muted-foreground">
            {label}
          </span>
        ))}

        {days.map((day, index) => {
          if (day === null) return <span key={`vazio-${index}`} />;

          const disabled = max !== undefined && day > max;
          const isFrom = day === preview.from;
          const isTo = day === preview.to;
          const inside = day > preview.from && day < preview.to;

          return (
            <button
              key={day}
              type="button"
              disabled={disabled}
              onClick={() => pick(day)}
              onMouseEnter={() => anchor && setHovered(day)}
              aria-label={longLabel(day)}
              aria-pressed={isFrom || isTo || inside}
              className={cn(
                "relative mx-auto flex size-9 items-center justify-center text-sm tabular-nums transition-colors",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                disabled && "cursor-not-allowed text-muted-foreground/40",
                !disabled && !isFrom && !isTo && !inside && "rounded-lg hover:bg-accent",
                inside && "w-full rounded-none bg-accent text-accent-foreground",
                (isFrom || isTo) && "bg-primary font-medium text-primary-foreground",
                // As pontas arredondam só do lado de fora do intervalo: no
                // meio, os dias se encostam e formam uma faixa contínua.
                isFrom && !isTo && "w-full rounded-l-lg rounded-r-none",
                isTo && !isFrom && "w-full rounded-r-lg rounded-l-none",
                isFrom && isTo && "rounded-lg",
              )}
            >
              {Number(day.slice(8))}
            </button>
          );
        })}
      </div>

      <p className="text-center text-xs text-muted-foreground">
        {anchor
          ? "Agora escolha o fim do intervalo."
          : `${brief(selected.from)} até ${brief(selected.to)}`}
      </p>
    </div>
  );
};

type Cursor = { year: number; month: number };

const pad = (value: number) => String(value).padStart(2, "0");

const iso = (year: number, month: number, day: number) =>
  `${year}-${pad(month + 1)}-${pad(day)}`;

const monthOf = (date: string): Cursor => ({
  year: Number(date.slice(0, 4)),
  month: Number(date.slice(5, 7)) - 1,
});

const startOfMonth = (cursor: Cursor) => iso(cursor.year, cursor.month, 1);

function shiftMonth(cursor: Cursor, by: number): Cursor {
  const month = cursor.month + by;

  if (month < 0) return { year: cursor.year - 1, month: 11 };
  if (month > 11) return { year: cursor.year + 1, month: 0 };

  return { year: cursor.year, month };
}

/** Os dias do mês, precedidos dos vazios que alinham o primeiro à semana. */
function grid(cursor: Cursor): (string | null)[] {
  const first = new Date(cursor.year, cursor.month, 1).getDay();
  const total = new Date(cursor.year, cursor.month + 1, 0).getDate();

  return [
    ...Array.from({ length: first }, () => null),
    ...Array.from({ length: total }, (_, index) => iso(cursor.year, cursor.month, index + 1)),
  ];
}

/** Datas em ISO comparam como texto; a menor é sempre o começo. */
const order = (a: string, b: string): DateRange =>
  a <= b ? { from: a, to: b } : { from: b, to: a };

const brief = (date: string) => date.split("-").reverse().slice(0, 2).join("/");

const longLabel = (date: string) => {
  const cursor = monthOf(date);
  return `${Number(date.slice(8))} de ${MONTHS[cursor.month]} de ${cursor.year}`;
};
