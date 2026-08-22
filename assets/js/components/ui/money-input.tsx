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
  /**
   * Casas decimais da máscara. Duas para dinheiro; quatro para preço e custo
   * por grama, onde os centavos escondem a diferença entre 0,062 e 0,068.
   */
  decimals?: number;
};

/**
 * Campo de dinheiro com máscara.
 *
 * Os dígitos entram pela direita — digitar "6", "2", "0", "0" mostra
 * "0,06", "0,62", "6,20", "62,00" — então não há vírgula para acertar no
 * teclado do celular, nem como digitar letra ou dois separadores.
 *
 * O que vai para o `onChange` é sempre o valor canônico ("1234,56"); o
 * separador de milhar existe só na tela. O servidor recebe o mesmo formato
 * que já recebia de um input solto.
 */
const MoneyInput = React.forwardRef<HTMLInputElement, MoneyInputProps>(
  ({ className, value, onChange, decimals = 2, ...props }, ref) => {
    const inner = React.useRef<HTMLInputElement | null>(null);

    const handle = (event: React.ChangeEvent<HTMLInputElement>) => {
      onChange(maskMoney(event.target.value, decimals));

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
          value={moneyDisplay(value, decimals)}
          onChange={handle}
          placeholder={moneyDisplay("0", decimals)}
          className={cn("pl-9 tabular-nums", className)}
          {...props}
        />
      </div>
    );
  },
);
MoneyInput.displayName = "MoneyInput";

export { MoneyInput };
