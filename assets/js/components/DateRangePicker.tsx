import * as React from "react";
import { router } from "@inertiajs/react";
import { CalendarDays } from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Calendar, type DateRange } from "@/components/ui/calendar";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

export type Range = DateRange;

/** Atalhos calculados a partir de "hoje" do servidor, não do relógio do aparelho. */
function presets(today: string): { id: string; label: string; range: Range }[] {
  const shift = (days: number) => {
    const date = new Date(`${today}T12:00:00`);
    date.setDate(date.getDate() - days);
    return date.toISOString().slice(0, 10);
  };

  const monthStart = `${today.slice(0, 7)}-01`;

  return [
    { id: "hoje", label: "Hoje", range: { from: today, to: today } },
    { id: "ontem", label: "Ontem", range: { from: shift(1), to: shift(1) } },
    { id: "7d", label: "7 dias", range: { from: shift(6), to: today } },
    { id: "mes", label: "Mês", range: { from: monthStart, to: today } },
  ];
}

/**
 * Recorte de datas do painel. Atalhos primeiro, porque é o que se usa no dia
 * a dia; o intervalo livre fica atrás de um botão para não ocupar a tela do
 * celular com um calendário que quase ninguém abre.
 *
 * A navegação é `router.get` com `preserveState: false` de propósito: os
 * blocos do painel buscam o próprio dado ao aparecer, e só voltam a buscar se
 * remontarem — preservar o estado deixaria cada categoria exibindo o número
 * do período anterior.
 */
export const DateRangePicker: React.FC<{ range: Range; today: string }> = ({
  range,
  today,
}) => {
  const options = presets(today);
  const active = options.find(
    (option) => option.range.from === range.from && option.range.to === range.to,
  );

  const apply = (next: Range) =>
    router.get(
      "/",
      { de: next.from, ate: next.to },
      { preserveState: false, preserveScroll: true, replace: true },
    );

  return (
    <div className="flex items-center gap-2 overflow-x-auto pb-1">
      {options.map((option) => (
        <Button
          key={option.id}
          variant={active?.id === option.id ? "default" : "outline"}
          size="sm"
          aria-pressed={active?.id === option.id}
          className="shrink-0 rounded-full px-3.5"
          onClick={() => apply(option.range)}
        >
          {option.label}
        </Button>
      ))}

      <CustomRange range={range} today={today} onApply={apply} custom={!active} />
    </div>
  );
};

const CustomRange: React.FC<{
  range: Range;
  today: string;
  custom: boolean;
  onApply: (range: Range) => void;
}> = ({ range, today, custom, onApply }) => {
  const [open, setOpen] = React.useState(false);
  const [draft, setDraft] = React.useState(range);

  // Reabrir o seletor deve mostrar o intervalo em vigor, não o que foi
  // escolhido e abandonado da última vez.
  React.useEffect(() => {
    if (open) setDraft(range);
  }, [open, range]);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button
          variant={custom ? "default" : "outline"}
          size="sm"
          aria-pressed={custom}
          className={cn("shrink-0 rounded-full px-3.5")}
        >
          <CalendarDays className="size-4" />
          {custom ? `${brief(range.from)} – ${brief(range.to)}` : "Período"}
        </Button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <DialogTitle>Escolher período</DialogTitle>
          <DialogDescription>
            Toque no primeiro dia e depois no último.
          </DialogDescription>
        </DialogHeader>

        {/* `max={today}`: não há venda no futuro, e um intervalo que termina
            amanhã só devolveria os mesmos números com uma data estranha. */}
        <Calendar selected={draft} onSelect={setDraft} max={today} />

        <DialogFooter>
          <Button
            size="sm"
            onClick={() => {
              onApply(draft);
              setOpen(false);
            }}
          >
            Aplicar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

const brief = (iso: string) => iso.split("-").reverse().slice(0, 2).join("/");
