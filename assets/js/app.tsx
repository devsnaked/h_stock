import * as React from "react";
import { createInertiaApp, router } from "@inertiajs/react";
import { createRoot } from "react-dom/client";
import type { SharedProps } from "./types";

// O Phoenix protege todo POST/PUT/DELETE com CSRF. O token vem em dois
// lugares: a `<meta>` renderizada no boot e o prop `csrfToken`, publicado a
// cada resposta pelo `Web.Plugs.SetCurrentUser`. O prop é a fonte confiável —
// o token é rotacionado no login/logout e a meta tag ficaria velha depois da
// primeira navegação SPA.
function currentCsrfToken(): string | null {
  const fromProps = (
    window as Window & {
      __inertia?: { page?: { props?: { csrfToken?: string } } };
    }
  ).__inertia?.page?.props?.csrfToken;

  if (fromProps) return fromProps;

  return (
    document.querySelector("meta[name='csrf-token']")?.getAttribute("content") ??
    null
  );
}

router.on("before", (event) => {
  const token = currentCsrfToken();
  if (token) event.detail.visit.headers["x-csrf-token"] = token;

  // Fade entre páginas via View Transitions API. O Inertia troca o DOM por
  // dentro da transição, então o fade-out da tela antiga e o fade-in da nova
  // acontecem no mesmo instante — a página nunca fica em branco esperando a
  // resposta do servidor. A aparência do fade está no `app.css`; navegador
  // sem suporte à API simplesmente troca sem animação.
  event.detail.visit.viewTransition = true;
});

// Mantém a meta tag sincronizada para código fora do ciclo de vida do
// Inertia (um `fetch` manual, por exemplo).
router.on("success", (event) => {
  const next = (event.detail.page.props as Partial<SharedProps>).csrfToken;
  if (!next) return;
  document
    .querySelector<HTMLMetaElement>("meta[name='csrf-token']")
    ?.setAttribute("content", next);
});

type PageModule = { default: React.ComponentType<Record<string, unknown>> };

const NotFound: React.FC<{ name: string }> = ({ name }) => (
  <div className="min-h-screen flex items-center justify-center bg-background text-foreground">
    <div className="text-center">
      <h1 className="text-2xl font-semibold">Página não encontrada</h1>
      <p className="mt-2 text-muted-foreground">
        Faltou o arquivo{" "}
        <code className="font-mono">assets/js/pages/{name}.tsx</code>.
      </p>
    </div>
  </div>
);

// O controller devolve `component: "Auth/SignIn"`; aqui isso vira
// `./pages/Auth/SignIn.tsx`. Cada `import()` dinâmico vira um chunk separado
// por causa do `--splitting` do esbuild, então uma página nunca carrega o
// código das outras.
//
// Toda página é um arquivo único — não há convenção de pasta com
// `index.tsx`. Se um dia houver, o import dela precisa entrar aqui.
async function resolvePage(name: string): Promise<PageModule> {
  try {
    return (await import(`./pages/${name}.tsx`)) as PageModule;
  } catch (error) {
    console.error(`Página não encontrada: ${name}`, error);
    return { default: () => <NotFound name={name} /> };
  }
}

createInertiaApp({
  resolve: (name) => resolvePage(name),
  setup({ App, el, props }) {
    createRoot(el).render(<App {...props} />);
  },
  progress: {
    color: "#4f46e5",
  },
});
