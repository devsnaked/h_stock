import * as React from "react";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { maskMoney, moneyDisplay } from "@/lib/format";

type MoneyInputProps = Omit<
  React.InputHTMLAttributes<HTMLInputElement>,
  "value" | "onChange" | "type" | "inputMode"
> & {
  /** Valor canônico do formulário: vírgula decimal, sem separador de milhar. */
  value: string;
  onChange: (value: string) => void;
};

/**
 * Campo de dinheiro com máscara.
 *
 * Os dígitos entram pela direita — digitar "6", "2", "0", "0" mostra
 * "0,06", "0,62", "6,20", "62,00" — então não há vírgula para acertar no
 * teclado do celular, nem como digitar letra ou dois separadores.
 *
 * Sempre reais e centavos, duas casas: é o que se escreve num preço no
 * Brasil. Preço por grama abaixo de um centavo não cabe aqui — esse produto
 * se cadastra por kg, que é como ele é falado no balcão de qualquer forma.
 *
 * O que vai para o `onChange` é sempre o valor canônico ("1234,56"); o
 * separador de milhar existe só na tela. O servidor recebe o mesmo formato
 * que já recebia de um input solto.
 */
const MoneyInput = React.forwardRef<HTMLInputElement, MoneyInputProps>(
  ({ className, value, onChange, ...props }, ref) => {
    const inner = React.useRef<HTMLInputElement | null>(null);

    const handle = (event: React.ChangeEvent<HTMLInputElement>) => {
      onChange(maskMoney(event.target.value));

      // A máscara reescreve o campo inteiro a cada tecla; sem isto o cursor
      // pularia para o começo no meio da digitação em alguns navegadores.
      requestAnimationFrame(() => {
        const el = inner.current;
        if (el) el.setSelectionRange(el.value.length, el.value.length);
      });
    };

    return (
      <div className="relative">
        <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">
          R$
        </span>

        <Input
          ref={(node) => {
            inner.current = node;
            if (typeof ref === "function") ref(node);
            else if (ref) ref.current = node;
          }}
          inputMode="numeric"
          value={moneyDisplay(value)}
          onChange={handle}
          placeholder={moneyDisplay("0")}
          className={cn("pl-9 tabular-nums", className)}
          {...props}
        />
      </div>
    );
  },
);
MoneyInput.displayName = "MoneyInput";

export { MoneyInput };
