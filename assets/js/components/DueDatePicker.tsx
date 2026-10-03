import * as React from "react";
import { CalendarDays } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Calendar } from "@/components/ui/calendar";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { dateLabel } from "@/lib/format";

const weekday = new Intl.DateTimeFormat("pt-BR", { weekday: "long" });

/**
 * O dia em que a venda a prazo vai ser paga.
 *
 * O combinado no balcão quase sempre é "daqui a uma semana", "daqui a quinze
 * dias" ou "no fim do mês" — por isso os atalhos vêm primeiro, e o calendário
 * fica atrás de um botão para o dia que não cai em nenhum deles.
 *
 * Tudo parte do `today` do servidor (o dia da loja), não do relógio do
 * aparelho, e o calendário não deixa escolher dia passado — o domínio também
 * não aceitaria.
 */
export const DueDatePicker: React.FC<{
  today: string;
  /** Data ISO escolhida, ou vazio. */
  value: string;
  onChange: (value: string) => void;
}> = ({ today, value, onChange }) => {
  const [open, setOpen] = React.useState(false);

  // Meio-dia, e não meia-noite: somar dias a partir daí nunca atravessa a
  // virada do dia por causa do fuso ou do horário de verão.
  const shift = (days: number) => {
    const date = new Date(`${today}T12:00:00`);
    date.setDate(date.getDate() + days);
    return date.toISOString().slice(0, 10);
  };

  const monthEnd = (() => {
    const date = new Date(`${today}T12:00:00`);
    date.setMonth(date.getMonth() + 1, 0);
    return date.toISOString().slice(0, 10);
  })();

  const presets = [
    { label: "7 dias", date: shift(7) },
    { label: "15 dias", date: shift(15) },
    { label: "30 dias", date: shift(30) },
    { label: "Fim do mês", date: monthEnd },
  ];

  const custom = value !== "" && !presets.some((preset) => preset.date === value);

  return (
    <div className="space-y-2">
      {/* Quebra em vez de rolar: "Outro dia" escondido à direita seria a
          opção que ninguém acha. */}
      <div className="flex flex-wrap items-center gap-2">
        {presets.map((preset) => (
          <Button
            key={preset.label}
            type="button"
            size="sm"
            variant={value === preset.date ? "default" : "outline"}
            aria-pressed={value === preset.date}
            className="rounded-full px-3.5"
            onClick={() => onChange(preset.date)}
          >
            {preset.label}
          </Button>
        ))}

        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button
              type="button"
              size="sm"
              variant={custom ? "default" : "outline"}
              aria-pressed={custom}
              className="rounded-full px-3.5"
            >
              <CalendarDays className="size-4" />
              {custom ? dateLabel(value).slice(0, 5) : "Outro dia"}
            </Button>
          </DialogTrigger>

          <DialogContent>
            <DialogHeader>
              <DialogTitle>Dia do pagamento</DialogTitle>
              <DialogDescription>Toque no dia combinado com o cliente.</DialogDescription>
            </DialogHeader>

            <Calendar
              single
              min={today}
              selected={{ from: value, to: value }}
              onSelect={(range) => {
                onChange(range.from);
                setOpen(false);
              }}
            />
          </DialogContent>
        </Dialog>
      </div>

      <p className="text-xs text-muted-foreground">
        {value === ""
          ? "Escolha quando o cliente vai pagar."
          : `Vence ${weekday.format(new Date(`${value}T12:00:00`))}, ${dateLabel(value)}.`}
      </p>
    </div>
  );
};
