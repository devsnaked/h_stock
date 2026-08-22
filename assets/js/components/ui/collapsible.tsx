import * as React from "react";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Bloco que abre e fecha.
 *
 * Substitui o `<details>` nativo, que traz a setinha do sistema, não anima e
 * não obedece aos tokens do tema. Aqui o cabeçalho inteiro é o alvo de toque
 * — no celular, uma seta de 10px não é alvo.
 *
 * O conteúdo continua no DOM quando fechado (só escondido), então o que já
 * foi carregado não precisa ser montado de novo a cada abertura. Onde isso
 * não interessa — categoria do painel que buscaria dado à toa —, quem chama
 * decide não renderizar.
 */
export const Collapsible: React.FC<{
  /** O que aparece na linha do cabeçalho. */
  label: React.ReactNode;
  defaultOpen?: boolean;
  className?: string;
  children: React.ReactNode;
}> = ({ label, defaultOpen = false, className, children }) => {
  const [open, setOpen] = React.useState(defaultOpen);
  const id = React.useId();

  return (
    <div className={cn("space-y-2", className)}>
      <button
        type="button"
        onClick={() => setOpen(!open)}
        aria-expanded={open}
        aria-controls={id}
        className="flex w-full items-center gap-1.5 rounded-lg py-1 text-left text-xs text-muted-foreground transition-colors hover:text-foreground"
      >
        <ChevronDown className={cn("size-3.5 transition-transform", !open && "-rotate-90")} />
        {label}
      </button>

      <div id={id} hidden={!open}>
        {children}
      </div>
    </div>
  );
};
