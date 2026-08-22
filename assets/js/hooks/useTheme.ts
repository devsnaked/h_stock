import * as React from "react";

export type Theme = "light" | "dark" | "system";

/**
 * Tema do app.
 *
 * Quem manda é o `data-theme` no `<html>`, aplicado por um script inline
 * **antes do primeiro paint** (ver o root layout) — sem isso a tela piscaria
 * branca antes de ficar escura. Este hook só lê e escreve o mesmo contrato:
 * `localStorage.theme` guarda a escolha ("light"/"dark"), e a ausência dela
 * quer dizer "seguir o sistema".
 *
 * `data-theme-source` diz qual dos dois está valendo, e é o que faz o app
 * acompanhar a troca de tema do celular ao anoitecer quando ninguém escolheu
 * nada.
 */
export function useTheme(): [Theme, (theme: Theme) => void] {
  const [theme, setTheme] = React.useState<Theme>("system");

  React.useEffect(() => {
    try {
      setTheme((window.localStorage.getItem("theme") as Theme | null) ?? "system");
    } catch {
      // Armazenamento bloqueado: fica no padrão do sistema.
    }
  }, []);

  const change = React.useCallback((next: Theme) => {
    setTheme(next);

    const root = document.documentElement;
    const system = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";

    if (next === "system") {
      root.setAttribute("data-theme", system);
      root.setAttribute("data-theme-source", "system");
    } else {
      root.setAttribute("data-theme", next);
      root.setAttribute("data-theme-source", "user");
    }

    try {
      if (next === "system") window.localStorage.removeItem("theme");
      else window.localStorage.setItem("theme", next);
    } catch {
      // idem: a escolha vale para esta sessão, só não é lembrada.
    }
  }, []);

  return [theme, change];
}
