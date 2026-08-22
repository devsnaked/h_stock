import * as React from "react";
import { cn } from "@/lib/utils";
import type { Unit } from "@/types";

/**
 * Alternador grama/quilo. Dois botões grandes em vez de um select: é a
 * escolha mais repetida do app e precisa ser de um toque só.
 */
export const UnitToggle: React.FC<{
  value: Unit;
  onChange: (unit: Unit) => void;
  className?: string;
}> = ({ value, onChange, className }) => (
  <div
    role="group"
    aria-label="Unidade"
    className={cn("grid grid-cols-2 gap-1 rounded-lg bg-muted p-1", className)}
  >
    {(["g", "kg"] as const).map((unit) => (
      <button
        key={unit}
        type="button"
        onClick={() => onChange(unit)}
        aria-pressed={value === unit}
        className={cn(
          "h-9 rounded-md text-sm font-medium transition-colors",
          value === unit
            ? "bg-card text-foreground shadow-sm"
            : "text-muted-foreground hover:text-foreground",
        )}
      >
        {unit === "g" ? "gramas" : "quilos"}
      </button>
    ))}
  </div>
);
