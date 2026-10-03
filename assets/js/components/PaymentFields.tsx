import * as React from "react";
import { Field } from "@/components/ui/label";
import { DueDatePicker } from "@/components/DueDatePicker";

/**
 * À vista ou a prazo, e o dia combinado — o mesmo bloco no registro e na
 * edição do pedido.
 *
 * Voltar para à vista não apaga a data: se a pessoa mudar de ideia de novo, o
 * dia escolhido continua lá. Quem decide o que vale é o servidor, que ignora
 * a data na venda à vista.
 */
export const PaymentFields: React.FC<{
  today: string;
  onCredit: boolean;
  dueOn: string;
  error?: string;
  onCreditChange: (onCredit: boolean) => void;
  onDueOnChange: (dueOn: string) => void;
}> = ({ today, onCredit, dueOn, error, onCreditChange, onDueOnChange }) => (
  <div className="space-y-3">
    <div
      role="group"
      aria-label="Forma de pagamento"
      className="grid grid-cols-2 gap-1 rounded-lg bg-muted p-1"
    >
      {(
        [
          [false, "À vista"],
          [true, "A prazo"],
        ] as const
      ).map(([value, label]) => (
        <button
          key={label}
          type="button"
          onClick={() => onCreditChange(value)}
          aria-pressed={onCredit === value}
          className={
            onCredit === value
              ? "h-9 rounded-md bg-card text-sm font-medium shadow-sm"
              : "h-9 rounded-md text-sm font-medium text-muted-foreground"
          }
        >
          {label}
        </button>
      ))}
    </div>

    {onCredit && (
      <Field label="Vence em" error={error}>
        <DueDatePicker today={today} value={dueOn} onChange={onDueOnChange} />
      </Field>
    )}
  </div>
);
