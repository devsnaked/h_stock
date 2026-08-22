import * as React from "react";
import { Monitor, Moon, Sun } from "lucide-react";
import { cn } from "@/lib/utils";
import { useTheme, type Theme } from "@/hooks/useTheme";

const OPTIONS: { id: Theme; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
  { id: "light", label: "Claro", icon: Sun },
  { id: "dark", label: "Escuro", icon: Moon },
  { id: "system", label: "Sistema", icon: Monitor },
];

/**
 * Escolha do tema, no mesmo controle segmentado das permissões — três opções
 * lado a lado, sem menu.
 *
 * "Sistema" é o padrão de propósito: o celular do balcão costuma escurecer
 * sozinho ao anoitecer, e o app acompanha sem ninguém pedir. As outras duas
 * existem para quem trabalha num lugar onde essa regra não serve — vitrine
 * ensolarada, câmara fria escura.
 */
export const ThemeToggle: React.FC = () => {
  const [theme, setTheme] = useTheme();

  return (
    <div
      role="group"
      aria-label="Tema"
      className="grid grid-cols-3 gap-1 rounded-lg bg-muted p-1"
    >
      {OPTIONS.map(({ id, label, icon: Icon }) => (
        <button
          key={id}
          type="button"
          onClick={() => setTheme(id)}
          aria-pressed={theme === id}
          className={cn(
            "flex h-9 items-center justify-center gap-1.5 rounded-md text-sm font-medium transition-colors",
            theme === id
              ? "bg-card text-foreground shadow-sm"
              : "text-muted-foreground hover:text-foreground",
          )}
        >
          <Icon className="size-4" />
          {label}
        </button>
      ))}
    </div>
  );
};
