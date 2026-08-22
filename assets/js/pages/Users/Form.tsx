import * as React from "react";
import { router, useForm } from "@inertiajs/react";
import { AppLayout } from "@/layouts/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
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
import { fieldErrors } from "@/lib/errors";
import type { DashboardSection, Role, User } from "@/types";

type Props = { user: User | null };

export default function UserForm({ user }: Props) {
  const editing = user !== null;

  return (
    <AppLayout
      title={editing ? user.name : "Nova pessoa"}
      subtitle={editing ? `@${user.nickname}` : "Cadastro de acesso"}
      back="/usuarios"
    >
      <div className="space-y-4">
        {editing ? (
          <>
            <PermissionsForm user={user} />
            <PasswordForm user={user} />
            <TwoFactor user={user} />
          </>
        ) : (
          <CreateForm />
        )}
      </div>
    </AppLayout>
  );
}

const CreateForm: React.FC = () => {
  const form = useForm({
    name: "",
    nickname: "",
    password: "",
    password_confirmation: "",
    role: "employee" as Role,
    can_manage_stock: false,
    can_manage_orders: false,
    can_view_dashboard: false,
    dashboard_sections: [] as DashboardSection[],
  });

  const { data, setData, post, processing } = form;
  const errors = fieldErrors(form.errors);

  return (
    <form
      className="space-y-4"
      onSubmit={(event) => {
        event.preventDefault();
        post("/usuarios");
      }}
    >
      <Card>
        <CardContent className="space-y-4 p-4">
          <Field label="Nome" htmlFor="name" error={errors.name}>
            <Input
              id="name"
              required
              autoFocus
              value={data.name}
              onChange={(e) => setData("name", e.target.value)}
              aria-invalid={Boolean(errors.name)}
            />
          </Field>

          <Field
            label="Login"
            htmlFor="nickname"
            error={errors.nickname}
            hint="É o que a pessoa digita para entrar. Sem espaços; maiúsculas não importam."
          >
            <Input
              id="nickname"
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              autoComplete="username"
              required
              minLength={3}
              placeholder="maria.silva"
              value={data.nickname}
              onChange={(e) => setData("nickname", e.target.value)}
              aria-invalid={Boolean(errors.nickname)}
            />
          </Field>

          <Field
            label="Senha"
            htmlFor="password"
            error={errors.password}
            hint="Mínimo de 8 caracteres. A pessoa pode trocar depois."
          >
            <Input
              id="password"
              type="password"
              required
              minLength={8}
              autoComplete="new-password"
              value={data.password}
              onChange={(e) => setData("password", e.target.value)}
              aria-invalid={Boolean(errors.password)}
            />
          </Field>

          <Field
            label="Confirmar senha"
            htmlFor="password_confirmation"
            error={errors.password_confirmation}
          >
            <Input
              id="password_confirmation"
              type="password"
              required
              minLength={8}
              autoComplete="new-password"
              value={data.password_confirmation}
              onChange={(e) => setData("password_confirmation", e.target.value)}
            />
          </Field>
        </CardContent>
      </Card>

      <PermissionFields
        role={data.role}
        canManageStock={data.can_manage_stock}
        canManageOrders={data.can_manage_orders}
        onRole={(role) => setData("role", role)}
        onCanManageStock={(value) => setData("can_manage_stock", value)}
        onCanManageOrders={(value) => setData("can_manage_orders", value)}
      />

      <DashboardFields
        role={data.role}
        canViewDashboard={data.can_view_dashboard}
        sections={data.dashboard_sections}
        onCanViewDashboard={(value) => setData("can_view_dashboard", value)}
        onSections={(sections) => setData("dashboard_sections", sections)}
      />

      {errors.form && <p className="text-sm font-medium text-destructive">{errors.form}</p>}

      <Button type="submit" size="sm" className="w-full" disabled={processing}>
        {processing ? "Cadastrando..." : "Cadastrar"}
      </Button>
    </form>
  );
};

const PermissionsForm: React.FC<{ user: User }> = ({ user }) => {
  const form = useForm({
    role: user.role,
    can_manage_stock: user.canManageStock,
    can_manage_orders: user.canManageOrders,
    can_view_dashboard: user.canViewDashboard,
    dashboard_sections: user.dashboardSections,
  });

  const { data, setData, put, processing } = form;
  const errors = fieldErrors(form.errors);

  return (
    <form
      className="space-y-4"
      onSubmit={(event) => {
        event.preventDefault();
        put(`/usuarios/${user.id}`);
      }}
    >
      <PermissionFields
        role={data.role}
        canManageStock={data.can_manage_stock}
        canManageOrders={data.can_manage_orders}
        onRole={(role) => setData("role", role)}
        onCanManageStock={(value) => setData("can_manage_stock", value)}
        onCanManageOrders={(value) => setData("can_manage_orders", value)}
      />

      <DashboardFields
        role={data.role}
        canViewDashboard={data.can_view_dashboard}
        sections={data.dashboard_sections}
        onCanViewDashboard={(value) => setData("can_view_dashboard", value)}
        onSections={(sections) => setData("dashboard_sections", sections)}
      />

      {errors.form && <p className="text-sm font-medium text-destructive">{errors.form}</p>}

      <Button type="submit" size="sm" className="w-full" disabled={processing}>
        {processing ? "Salvando..." : "Salvar permissões"}
      </Button>
    </form>
  );
};

const PasswordForm: React.FC<{ user: User }> = ({ user }) => {
  const { data, setData, post, processing, errors, reset } = useForm({
    password: "",
    password_confirmation: "",
  });

  return (
    <form
      className="space-y-4"
      onSubmit={(event) => {
        event.preventDefault();
        post(`/usuarios/${user.id}/senha`, { onSuccess: () => reset() });
      }}
    >
      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Redefinir senha</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <Field
            label="Nova senha"
            htmlFor="new_password"
            error={errors.password}
            hint="Use quando a pessoa esquecer a senha."
          >
            <Input
              id="new_password"
              type="password"
              minLength={8}
              autoComplete="new-password"
              value={data.password}
              onChange={(e) => setData("password", e.target.value)}
              aria-invalid={Boolean(errors.password)}
            />
          </Field>

          <Field
            label="Confirmar nova senha"
            htmlFor="new_password_confirmation"
            error={errors.password_confirmation}
          >
            <Input
              id="new_password_confirmation"
              type="password"
              minLength={8}
              autoComplete="new-password"
              value={data.password_confirmation}
              onChange={(e) => setData("password_confirmation", e.target.value)}
            />
          </Field>

          <Button
            type="submit"
            variant="outline"
            className="w-full"
            disabled={processing || data.password === ""}
          >
            {processing ? "Salvando..." : "Definir nova senha"}
          </Button>
        </CardContent>
      </Card>
    </form>
  );
};

/**
 * Verificação em duas etapas de outra pessoa. O admin não consegue ligar (o
 * segredo mora no celular dela), só desligar — que é a saída para quem perdeu
 * o aparelho e gastou os códigos de recuperação.
 */
const TwoFactor: React.FC<{ user: User }> = ({ user }) => (
  <Card>
    <CardHeader className="flex-row items-center justify-between">
      <CardTitle className="text-sm">Verificação em duas etapas</CardTitle>
      <Badge variant={user.twoFactor ? "default" : "outline"}>
        {user.twoFactor ? "ativa" : "desligada"}
      </Badge>
    </CardHeader>

    <CardContent>
      {user.twoFactor ? (
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button variant="outline" className="w-full text-destructive">
              Desligar para {user.name.split(" ")[0]}
            </Button>
          </AlertDialogTrigger>

          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Desligar a verificação de {user.name}?</AlertDialogTitle>
              <AlertDialogDescription>
                Use quando a pessoa perdeu o celular e não tem mais códigos de
                recuperação. Ela volta a entrar só com a senha, e pode ativar de
                novo quando quiser.
              </AlertDialogDescription>
            </AlertDialogHeader>

            <AlertDialogFooter>
              <AlertDialogCancel>Voltar</AlertDialogCancel>
              <AlertDialogAction
                onClick={() => router.post(`/usuarios/${user.id}/2fa/desligar`)}
              >
                Desligar
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      ) : (
        <p className="text-sm text-muted-foreground">
          Só a própria pessoa pode ativar, em Segurança — o segredo fica no
          celular dela.
        </p>
      )}
    </CardContent>
  </Card>
);

/** Perfil + permissões, compartilhado entre criar e editar. */
const PermissionFields: React.FC<{
  role: Role;
  canManageStock: boolean;
  canManageOrders: boolean;
  onRole: (role: Role) => void;
  onCanManageStock: (value: boolean) => void;
  onCanManageOrders: (value: boolean) => void;
}> = ({
  role,
  canManageStock,
  canManageOrders,
  onRole,
  onCanManageStock,
  onCanManageOrders,
}) => {
  // Entregador não tem permissão nenhuma para dar: ele recebe pedido e marca
  // entrega. O domínio zera as duas de qualquer jeito
  // (`NormalizePermissions`); aqui é para a tela não prometer o que não vai
  // acontecer.
  const driver = role === "driver";

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm">Perfil e permissões</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div
          role="group"
          aria-label="Perfil"
          className="grid grid-cols-3 gap-1 rounded-lg bg-muted p-1"
        >
          {(
            [
              ["employee", "Funcionário"],
              ["driver", "Entregador"],
              ["admin", "Administrador"],
            ] as const
          ).map(([value, label]) => (
            <button
              key={value}
              type="button"
              onClick={() => onRole(value)}
              aria-pressed={role === value}
              className={
                role === value
                  ? "h-9 rounded-md bg-card text-sm font-medium shadow-sm"
                  : "h-9 rounded-md text-sm font-medium text-muted-foreground"
              }
            >
              {label}
            </button>
          ))}
        </div>

        <p className="text-xs text-muted-foreground">{ROLE_HINT[role]}</p>

        <label className="flex items-center justify-between gap-3">
          <span className="space-y-0.5">
            <span className="block text-sm font-medium">Gerenciar estoque</span>
            <span className="block text-xs text-muted-foreground">
              {role === "admin"
                ? "Administradores já gerenciam o estoque."
                : driver
                  ? "Entregador não abre o estoque."
                  : "Permite cadastrar produtos e movimentar o estoque."}
            </span>
          </span>
          <Switch
            checked={role === "admin" || (!driver && canManageStock)}
            disabled={role === "admin" || driver}
            onCheckedChange={onCanManageStock}
          />
        </label>

        <label className="flex items-center justify-between gap-3">
          <span className="space-y-0.5">
            <span className="block text-sm font-medium">Gerenciar pedidos</span>
            <span className="block text-xs text-muted-foreground">
              {role === "admin"
                ? "Administradores já enxergam os pedidos da loja."
                : driver
                  ? "Entregador só vê os pedidos que estão com ele."
                  : "Enxerga, cancela e despacha os pedidos de toda a equipe — sem isso, só os que a própria pessoa registrou."}
            </span>
          </span>
          <Switch
            checked={role === "admin" || (!driver && canManageOrders)}
            disabled={role === "admin" || driver}
            onCheckedChange={onCanManageOrders}
          />
        </label>
      </CardContent>
    </Card>
  );
};

/**
 * As seções de dados do painel, na ordem em que aparecem nele. A lista de
 * verdade é `Core.Accounts.Permissions.dashboard_sections/0` — aqui ficam só
 * os nomes e o que cada seção mostra, que é o que o admin precisa ler para
 * decidir.
 */
const DASHBOARD_SECTIONS: {
  value: DashboardSection;
  label: string;
  hint: string;
}[] = [
  {
    value: "sales",
    label: "Vendas",
    hint: "Faturamento, ticket médio, cancelamentos e a série por dia.",
  },
  { value: "hours", label: "Horários", hint: "A que horas a loja vende." },
  {
    value: "products",
    label: "Produtos",
    hint: "Ranking do que mais saiu, com o peso vendido.",
  },
  {
    value: "team",
    label: "Equipe",
    hint: "Quanto cada pessoa do balcão registrou.",
  },
  {
    value: "delivery",
    label: "Entrega",
    hint: "A fila de agora, o tempo até a porta e o desempenho por entregador.",
  },
  {
    value: "stock",
    label: "Estoque",
    hint: "Saldo de agora, o que está abaixo do mínimo e onde o dinheiro está parado.",
  },
  {
    value: "recent",
    label: "Últimos pedidos",
    hint: "Os pedidos mais recentes do período.",
  },
];

const ALL_SECTIONS = DASHBOARD_SECTIONS.map((section) => section.value);

/**
 * Permissões do painel: a chave que abre a tela e, dentro dela, uma chave por
 * seção de dados.
 *
 * Liberar o painel marca todas as seções — painel aberto e vazio não serve a
 * ninguém, e desmarcar o que sobra é mais rápido que marcar de uma em uma.
 * Fechar o painel esconde as seções em vez de deixá-las marcadas à espera: o
 * domínio esvazia a lista de quem não abre a tela
 * (`NormalizePermissions`), e a tela não deve prometer o contrário.
 */
const DashboardFields: React.FC<{
  role: Role;
  canViewDashboard: boolean;
  sections: DashboardSection[];
  onCanViewDashboard: (value: boolean) => void;
  onSections: (sections: DashboardSection[]) => void;
}> = ({ role, canViewDashboard, sections, onCanViewDashboard, onSections }) => {
  const admin = role === "admin";
  const driver = role === "driver";
  const open = admin || (!driver && canViewDashboard);

  const toggle = (section: DashboardSection, on: boolean) =>
    // Reconstrói pela ordem do painel, para a lista guardada ler como a tela.
    onSections(
      ALL_SECTIONS.filter((value) =>
        value === section ? on : sections.includes(value),
      ),
    );

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm">Painel da loja</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <label className="flex items-center justify-between gap-3">
          <span className="space-y-0.5">
            <span className="block text-sm font-medium">Ver o painel</span>
            <span className="block text-xs text-muted-foreground">
              {admin
                ? "Administradores já veem o painel inteiro."
                : driver
                  ? "Entregador não abre o painel."
                  : "Abre a tela inicial de análise. Sem isto, o dia começa nos pedidos."}
            </span>
          </span>
          <Switch
            checked={open}
            disabled={admin || driver}
            onCheckedChange={(value) => {
              onCanViewDashboard(value);
              if (value && sections.length === 0) onSections(ALL_SECTIONS);
            }}
          />
        </label>

        {open && (
          <div className="space-y-4 border-t border-border pt-4">
            <p className="text-xs text-muted-foreground">
              {admin
                ? "Todas as seções, por ser administrador."
                : "Escolha o que aparece no painel. Seção desmarcada não é escondida na tela: ela não é calculada nem enviada."}
            </p>

            {DASHBOARD_SECTIONS.map((section) => (
              <label
                key={section.value}
                className="flex items-center justify-between gap-3"
              >
                <span className="space-y-0.5">
                  <span className="block text-sm font-medium">{section.label}</span>
                  <span className="block text-xs text-muted-foreground">
                    {section.hint}
                  </span>
                </span>
                <Switch
                  checked={admin || sections.includes(section.value)}
                  disabled={admin}
                  onCheckedChange={(value) => toggle(section.value, value)}
                />
              </label>
            ))}

            <p className="border-t border-border pt-4 text-xs text-muted-foreground">
              Lucro e custo dentro das seções continuam presos à permissão de
              gerenciar estoque — liberar Vendas mostra o faturamento, não a
              margem.
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};

const ROLE_HINT: Record<Role, string> = {
  employee:
    "Registra pedidos no balcão e manda os prontos para um entregador.",
  driver:
    "Só a tela de entregas: recebe os pedidos que lhe mandam e marca a saída e a chegada.",
  admin: "Controla estoque, pedidos, equipe e o resumo da loja.",
};
