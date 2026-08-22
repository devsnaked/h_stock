import * as React from "react";
import { useForm } from "@inertiajs/react";
import { AuthLayout } from "@/layouts/AuthLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/label";

// Os endpoints do AshAuthentication esperam os campos aninhados sob o
// `subject_name` do recurso (`user`), daí o formato do payload.
type Form = {
  user: { nickname: string; password: string };
};

export default function SignIn() {
  const { data, setData, post, processing } = useForm<Form>({
    user: { nickname: "", password: "" },
  });

  const update = <K extends keyof Form["user"]>(key: K, value: Form["user"][K]) =>
    setData("user", { ...data.user, [key]: value });

  return (
    <AuthLayout
      title="h_stock"
      subtitle="Entre para registrar pedidos e controlar o estoque"
      footer={
        // Não há recuperação por e-mail: o sistema não guarda endereço. Quem
        // esquece a senha pede ao admin, que define uma nova em /usuarios.
        <span className="text-muted-foreground">
          Esqueceu a senha? Peça ao administrador para gerar uma nova.
        </span>
      }
    >
      <form
        className="space-y-4"
        onSubmit={(event) => {
          event.preventDefault();
          post("/auth/user/password/sign_in");
        }}
      >
        <Field label="Login" htmlFor="nickname">
          <Input
            id="nickname"
            autoComplete="username"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            autoFocus
            required
            value={data.user.nickname}
            onChange={(e) => update("nickname", e.target.value)}
          />
        </Field>

        <Field label="Senha" htmlFor="password">
          <Input
            id="password"
            type="password"
            autoComplete="current-password"
            required
            value={data.user.password}
            onChange={(e) => update("password", e.target.value)}
          />
        </Field>

        <Button type="submit" size="lg" className="w-full" disabled={processing}>
          {processing ? "Entrando..." : "Entrar"}
        </Button>
      </form>
    </AuthLayout>
  );
}
