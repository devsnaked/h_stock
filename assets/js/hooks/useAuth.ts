import { usePage, router } from "@inertiajs/react";
import type { SharedProps, User } from "@/types";

/**
 * Usuário atual + logout. Lê os props compartilhados, então funciona em
 * qualquer página sem o controller precisar passar nada.
 */
export function useAuth() {
  const { user } = usePage<SharedProps>().props;

  return {
    user,
    isAdmin: user?.role === "admin",
    /** Entregador: o app dele é só a lista de entregas. */
    isDriver: user?.role === "driver",
    /** admin ou funcionário autorizado — quem pode mexer no estoque. */
    managesStock: user?.managesStock === true,
    /** Quem alcança os pedidos da equipe inteira, não só os próprios. */
    managesOrders: user?.managesOrders === true,
    /** Quem abre o painel da loja — dentro dele, cada seção é outra permissão. */
    viewsDashboard: user?.viewsDashboard === true,
    signOut: () => router.delete("/sign-out"),
  };
}

/** Nas páginas atrás de login o usuário existe; evita `user?.` por toda parte. */
export function useCurrentUser(): User {
  const { user } = usePage<SharedProps>().props;

  if (!user) {
    throw new Error("Página autenticada renderizada sem usuário nos props.");
  }

  return user;
}
