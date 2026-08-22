import * as React from "react";
import { Toaster as SonnerToaster, toast } from "sonner";

type Theme = "light" | "dark";

const currentTheme = (): Theme =>
  document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light";

/**
 * Toaster do shadcn (sonner). Fica no topo à direita: a navegação principal do
 * app é a barra de baixo (um toast no rodapé cobriria os botões) e, no
 * desktop, o canto é onde o aviso menos atrapalha a leitura do conteúdo.
 *
 * O tema não vem de um contexto React: quem manda é o `data-theme` que um
 * script inline aplica no `<html>` antes do primeiro paint (ver o root
 * layout). O observer abaixo só repassa essa mudança para o sonner.
 */
export const Toaster: React.FC = () => {
  const [theme, setTheme] = React.useState<Theme>(currentTheme);

  React.useEffect(() => {
    const observer = new MutationObserver(() => setTheme(currentTheme()));

    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    });

    return () => observer.disconnect();
  }, []);

  return (
    <SonnerToaster
      theme={theme}
      position="top-right"
      // Abaixo do cabeçalho fixo (56px), senão o toast cobre o título da tela.
      offset={64}
      mobileOffset={64}
      duration={4000}
      // Sem `richColors` nem botão de fechar: o aviso usa as cores do próprio
      // tema e some sozinho, para ser lido de canto de olho e não virar um
      // cartão de diálogo no meio da tela.
      toastOptions={{
        classNames: {
          toast:
            "rounded-lg border border-border bg-card text-foreground shadow-sm",
          title: "text-sm font-medium",
          description: "text-xs text-muted-foreground",
          // Sem fundo colorido, o ícone é o que diferencia erro de sucesso.
          success: "[&_[data-icon]]:text-success",
          error: "[&_[data-icon]]:text-destructive",
        },
      }}
    />
  );
};

export { toast };
