import * as React from "react";
import { router, useForm } from "@inertiajs/react";
import { AuthLayout } from "@/layouts/AuthLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/label";

type Props = {
  /** `login` = senha conferida, falta o código. `reverify` = já logado, a
      validação passou de uma hora. */
  mode: "login" | "reverify";
  attemptsLeft: number;
};

export default function TwoFactor({ mode, attemptsLeft }: Props) {
  const reverifying = mode === "reverify";
  const { data, setData, post, processing } = useForm({ code: "" });
  const [recovery, setRecovery] = React.useState(false);

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    post("/verificacao");
  };

  return (
    <AuthLayout
      title={reverifying ? "Confirme que é você" : "Verificação"}
      subtitle={
        recovery
          ? "Digite um dos códigos de recuperação que você guardou"
          : reverifying
            ? "Faz mais de uma hora desde a última verificação. Digite o código do aplicativo para continuar."
            : "Abra o aplicativo autenticador e digite o código de 6 dígitos"
      }
      footer={
        reverifying ? (
          <button
            type="button"
            onClick={() => router.delete("/sign-out")}
            className="font-medium underline underline-offset-4"
          >
            Sair da conta
          </button>
        ) : (
          <button
            type="button"
            onClick={() => router.post("/verificacao/cancelar")}
            className="font-medium underline underline-offset-4"
          >
            Entrar com outra conta
          </button>
        )
      }
    >
      <form className="space-y-4" onSubmit={submit}>
        <Field label={recovery ? "Código de recuperação" : "Código"} htmlFor="code">
          <Input
            id="code"
            // `one-time-code` faz o teclado do celular sugerir o código e o
            // iOS oferecer o preenchimento automático.
            autoComplete="one-time-code"
            inputMode={recovery ? "text" : "numeric"}
            autoFocus
            required
            maxLength={recovery ? 12 : 6}
            placeholder={recovery ? "abc123" : "000000"}
            className={recovery ? "" : "text-center text-2xl tracking-[0.4em] tabular-nums"}
            value={data.code}
            onChange={(event) => setData("code", event.target.value)}
          />
        </Field>

        {!reverifying && attemptsLeft <= 2 && (
          <p className="text-xs font-medium text-destructive">
            {attemptsLeft} {attemptsLeft === 1 ? "tentativa restante" : "tentativas restantes"}.
          </p>
        )}

        <Button type="submit" size="lg" className="w-full" disabled={processing}>
          {processing ? "Conferindo..." : "Confirmar"}
        </Button>

        <button
          type="button"
          onClick={() => {
            setRecovery(!recovery);
            setData("code", "");
          }}
          className="w-full text-center text-sm text-muted-foreground underline underline-offset-4"
        >
          {recovery
            ? "Voltar ao código do aplicativo"
            : "Perdi o celular — usar código de recuperação"}
        </button>
      </form>
    </AuthLayout>
  );
}
