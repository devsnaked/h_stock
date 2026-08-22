import * as React from "react";
import { Head, Link, usePage } from "@inertiajs/react";
import { Bike, Boxes, ClipboardList, Home, LogOut, ShieldCheck, Users } from "lucide-react";
import { cn } from "@/lib/utils";
import type { Role } from "@/types";
import { useAuth } from "@/hooks/useAuth";
import { useFlashToasts } from "@/hooks/useFlashToasts";
import { Toaster } from "@/components/ui/sonner";
import { ThemeToggle } from "@/components/ThemeToggle";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";

type NavItem = {
  href: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  adminOnly?: boolean;
  /** Depende da permissão do painel (`can_view_dashboard`). */
  dashboardOnly?: boolean;
};

const NAV: NavItem[] = [
  { href: "/", label: "Início", icon: Home, dashboardOnly: true },
  { href: "/pedidos", label: "Pedidos", icon: ClipboardList },
  { href: "/produtos", label: "Estoque", icon: Boxes },
  { href: "/usuarios", label: "Equipe", icon: Users, adminOnly: true },
];

// O entregador tem uma tela só — as outras rotas nem abrem para ele
// (`Web.Plugs.RequireCounter`). O item único continua valendo: é o caminho de
// volta depois de abrir um pedido.
const DRIVER_NAV: NavItem[] = [{ href: "/entregas", label: "Entregas", icon: Bike }];

const ROLE_LABEL: Record<Role, string> = {
  admin: "administrador",
  employee: "funcionário",
  driver: "entregador",
};

/**
 * Casca das telas internas, desenhada para o celular: cabeçalho fino e
 * navegação numa barra inferior, ao alcance do polegar. A partir de `sm:` a
 * mesma barra ganha respiro, mas continua embaixo — é o mesmo app.
 */
export const AppLayout: React.FC<{
  title: string;
  subtitle?: string;
  /** Ação principal da tela, ancorada no topo à direita. */
  action?: React.ReactNode;
  /** Botão de voltar em vez do nome do app. */
  back?: string;
  children: React.ReactNode;
}> = ({ title, subtitle, action, back, children }) => {
  const { url } = usePage();
  const { isAdmin, isDriver, viewsDashboard } = useAuth();
  useFlashToasts();

  // Item que a pessoa não pode abrir não fica na barra: o plug do lado do
  // servidor devolveria ela para os pedidos, e um toque que sempre erra é pior
  // que um item de menos.
  const items = isDriver
    ? DRIVER_NAV
    : NAV.filter(
        (item) =>
          (!item.adminOnly || isAdmin) && (!item.dashboardOnly || viewsDashboard),
      );

  return (
    <div className="min-h-dvh bg-background text-foreground">
      <Head title={title} />
      <Toaster />

      <header className="sticky top-0 z-30 border-b border-border bg-card/95 backdrop-blur">
        <div className="mx-auto flex min-h-14 max-w-2xl items-center gap-3 px-4 py-2">
          {back && (
            <Link
              href={back}
              className="-ml-2 rounded-lg p-2 text-muted-foreground hover:text-foreground"
              aria-label="Voltar"
            >
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                className="size-5"
              >
                <path d="m15 18-6-6 6-6" />
              </svg>
            </Link>
          )}

          <div className="min-w-0 flex-1">
            <h1 className="truncate text-base font-semibold leading-tight">{title}</h1>
            {subtitle && (
              <p className="truncate text-xs text-muted-foreground">{subtitle}</p>
            )}
          </div>

          {action}

          {!back && <AccountMenu />}
        </div>
      </header>

      {/* pb-24: espaço para a barra inferior não cobrir o fim do conteúdo. */}
      <main className="mx-auto max-w-2xl px-4 pb-24 pt-4">{children}</main>

      <nav className="fixed inset-x-0 bottom-0 z-30 border-t border-border bg-card/95 backdrop-blur safe-bottom">
        <div className="mx-auto flex max-w-2xl">
          {items.map((item) => {
            const active =
              item.href === "/" ? url === "/" : url.startsWith(item.href);
            const Icon = item.icon;

            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  "flex flex-1 flex-col items-center gap-1 py-2.5 text-[11px] font-medium transition-colors",
                  active ? "text-primary" : "text-muted-foreground",
                )}
                aria-current={active ? "page" : undefined}
              >
                <Icon className="size-5" />
                {item.label}
              </Link>
            );
          })}
        </div>
      </nav>
    </div>
  );
};

/**
 * Conta do usuário atrás das iniciais no cabeçalho. Uma folha em vez de mais
 * um item na barra de baixo: são acessos raros (segurança, sair) e a barra
 * precisa ficar para o que se usa o dia inteiro.
 */
const AccountMenu: React.FC = () => {
  const { user, signOut } = useAuth();
  const [open, setOpen] = React.useState(false);

  if (!user) return null;

  const initials = user.name
    .split(" ")
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <button
          type="button"
          aria-label="Sua conta"
          className="flex size-9 shrink-0 items-center justify-center rounded-full bg-secondary text-xs font-semibold text-secondary-foreground"
        >
          {initials}
        </button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <DialogTitle>{user.name}</DialogTitle>
          <DialogDescription>
            @{user.nickname} · {ROLE_LABEL[user.role]}
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-3">
          <ThemeToggle />

          <Button variant="outline" asChild onClick={() => setOpen(false)}>
            <Link href="/seguranca">
              <ShieldCheck className="size-4" />
              Segurança
            </Link>
          </Button>

          <AlertDialog>
            <AlertDialogTrigger asChild>
              <Button variant="ghost" className="text-destructive">
                <LogOut className="size-4" />
                Sair da conta
              </Button>
            </AlertDialogTrigger>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>Sair da conta?</AlertDialogTitle>
                <AlertDialogDescription>
                  Vai precisar entrar de novo para registrar pedidos.
                </AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel>Ficar</AlertDialogCancel>
                <AlertDialogAction onClick={signOut}>Sair</AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        </div>
      </DialogContent>
    </Dialog>
  );
};
