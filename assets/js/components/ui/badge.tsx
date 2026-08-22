import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

/**
 * Badge é rótulo, não alarme.
 *
 * Nenhuma variante usa cor cheia: todas são um fundo de 10% com o texto na
 * própria cor. Numa tela onde quase todo pedido tem um badge, preenchimento
 * saturado vira ruído — e no tema escuro, onde a cor salta mais, vira farol.
 * A hierarquia sai da intensidade do cinza, não do tamanho da cor.
 */
const badgeVariants = cva(
  "inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-medium transition-colors",
  {
    variants: {
      variant: {
        default: "border-transparent bg-foreground/10 text-foreground",
        secondary: "border-transparent bg-muted text-muted-foreground",
        destructive: "border-destructive/25 bg-destructive/10 text-destructive",
        warning: "border-warning/25 bg-warning/10 text-warning-foreground",
        outline: "border-border text-muted-foreground",
      },
    },
    defaultVariants: { variant: "default" },
  },
);

export type BadgeProps = React.HTMLAttributes<HTMLSpanElement> &
  VariantProps<typeof badgeVariants>;

export const Badge: React.FC<BadgeProps> = ({ className, variant, ...props }) => (
  <span className={cn(badgeVariants({ variant }), className)} {...props} />
);
