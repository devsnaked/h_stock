import * as React from "react";
import { Link, router } from "@inertiajs/react";
import { Pencil, Plus, ShieldCheck } from "lucide-react";
import { AppLayout } from "@/layouts/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
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
import { useCurrentUser } from "@/hooks/useAuth";
import type { Role, User } from "@/types";

type Props = { users: User[] };

const ROLE_LABEL: Record<Role, string> = {
  admin: "admin",
  employee: "funcionário",
  driver: "entregador",
};

export default function UsersIndex({ users }: Props) {
  const me = useCurrentUser();

  return (
    <AppLayout
      title="Equipe"
      subtitle={`${users.length} ${users.length === 1 ? "pessoa" : "pessoas"}`}
      action={
        <Button asChild size="sm">
          <Link href="/usuarios/novo">
            <Plus className="size-4" />
            Novo
          </Link>
        </Button>
      }
    >
      <ul className="space-y-2">
        {users.map((user) => (
          <li key={user.id}>
            <Card>
              <CardContent className="flex items-center gap-3 p-4">
                <div className="min-w-0 flex-1 space-y-1">
                  <p className="truncate font-medium">
                    {user.name}
                    {user.id === me.id && (
                      <span className="ml-2 text-xs text-muted-foreground">você</span>
                    )}
                  </p>
                  <p className="truncate text-xs text-muted-foreground">{`@${user.nickname}`}</p>

                  <div className="flex flex-wrap gap-1 pt-1">
                    <Badge variant={user.role === "admin" ? "default" : "secondary"}>
                      {ROLE_LABEL[user.role]}
                    </Badge>
                    {user.role === "employee" && user.canManageStock && (
                      <Badge variant="outline">
                        <ShieldCheck className="size-3" />
                        gerencia estoque
                      </Badge>
                    )}
                    {user.role === "employee" && user.canManageOrders && (
                      <Badge variant="outline">
                        <ShieldCheck className="size-3" />
                        gerencia pedidos
                      </Badge>
                    )}
                    {/* Quantas seções, não quais: a lista inteira não cabe num
                        badge, e o número já diz se o painel dela é cheio ou
                        recortado. */}
                    {user.role === "employee" && user.canViewDashboard && (
                      <Badge variant="outline">
                        <ShieldCheck className="size-3" />
                        painel ({user.dashboardSections.length})
                      </Badge>
                    )}
                    {!user.active && <Badge variant="destructive">sem acesso</Badge>}
                  </div>
                </div>

                <div className="flex shrink-0 items-center gap-1">
                  <Button asChild variant="ghost" size="icon" aria-label={`Editar ${user.name}`}>
                    <Link href={`/usuarios/${user.id}/editar`}>
                      <Pencil className="size-4" />
                    </Link>
                  </Button>

                  {user.id !== me.id && <AccessToggle user={user} />}
                </div>
              </CardContent>
            </Card>
          </li>
        ))}
      </ul>
    </AppLayout>
  );
}

/** Bloquear/liberar acesso é destrutivo o bastante para pedir confirmação. */
const AccessToggle: React.FC<{ user: User }> = ({ user }) => {
  const blocking = user.active;

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="ghost" size="sm" className={blocking ? "text-destructive" : ""}>
          {blocking ? "Bloquear" : "Liberar"}
        </Button>
      </AlertDialogTrigger>

      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            {blocking ? `Bloquear ${user.name}?` : `Liberar ${user.name}?`}
          </AlertDialogTitle>
          <AlertDialogDescription>
            {blocking
              ? "A pessoa deixa de conseguir entrar no sistema. Os pedidos já registrados continuam no histórico."
              : "A pessoa volta a conseguir entrar com a mesma senha."}
          </AlertDialogDescription>
        </AlertDialogHeader>

        <AlertDialogFooter>
          <AlertDialogCancel>Voltar</AlertDialogCancel>
          <AlertDialogAction
            onClick={() =>
              router.post(`/usuarios/${user.id}/ativo`, { active: !user.active })
            }
          >
            {blocking ? "Bloquear acesso" : "Liberar acesso"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
};
