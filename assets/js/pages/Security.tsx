import * as React from "react";
import { router, useForm } from "@inertiajs/react";
import { Check, Copy, ShieldCheck, ShieldOff, Smartphone } from "lucide-react";
import { AppLayout } from "@/layouts/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/label";
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
import { dateTimeLabel } from "@/lib/format";

type Props = {
  twoFactor: {
    enabled: boolean;
    /** A verificação está sendo exigida para usar o sistema? */
    required: boolean;
    confirmedAt: string | null;
    recoveryCodesLeft: number;
  };
  /** Só presente durante a ativação, entre gerar o segredo e confirmar. */
  enrollment?: { qrCode: string; uri: string; secret: string };
  /** Só presente logo após confirmar — é a única vez que aparecem. */
  recoveryCodes?: string[];
};

export default function Security({ twoFactor, enrollment, recoveryCodes }: Props) {
  // Sem 2FA ativo — e com ele sendo exigido — não há para onde voltar: o
  // resto do sistema está fechado. Tirar a seta faz aparecer o menu da conta,
  // que ao menos permite sair. Com a exigência desligada, a tela é só mais
  // uma, e dá para sair dela.
  const back = twoFactor.enabled || !twoFactor.required ? "/" : undefined;

  return (
    <AppLayout title="Segurança" subtitle="Verificação em duas etapas" back={back}>
      <div className="space-y-4">
        {recoveryCodes ? (
          <RecoveryCodes codes={recoveryCodes} />
        ) : enrollment ? (
          <Enrollment enrollment={enrollment} />
        ) : twoFactor.enabled ? (
          <Enabled twoFactor={twoFactor} />
        ) : (
          <Disabled required={twoFactor.required} />
        )}
      </div>
    </AppLayout>
  );
}

const Disabled: React.FC<{ required: boolean }> = ({ required }) => (
  <Card>
    <CardHeader>
      <CardTitle className="flex items-center gap-2 text-sm">
        <Smartphone className="size-4 text-muted-foreground" />
        Verificação em duas etapas
      </CardTitle>
    </CardHeader>
    <CardContent className="space-y-4">
      {required ? (
        <p className="rounded-lg border border-warning/30 bg-warning/10 p-3 text-sm text-warning-foreground">
          O sistema só abre com a verificação ativa. Ative agora para continuar.
        </p>
      ) : (
        <p className="rounded-lg border border-border bg-muted p-3 text-sm text-muted-foreground">
          A verificação está desligada no sistema neste momento — dá para usar
          tudo sem ela. Ativar agora protege a sua conta do mesmo jeito, e você
          não precisará fazer nada quando ela voltar a ser exigida.
        </p>
      )}

      <p className="text-sm text-muted-foreground">
        Entrar passa a exigir a senha <em>e</em> um código de 6 dígitos gerado no
        seu celular. Serve qualquer aplicativo autenticador — Google
        Authenticator, Authy, 1Password, Microsoft Authenticator. O código é
        pedido de novo a cada hora de uso.
      </p>

      <Button size="sm" className="w-full" onClick={() => router.post("/seguranca/2fa")}>
        Ativar
      </Button>
    </CardContent>
  </Card>
);

const Enrollment: React.FC<{ enrollment: { qrCode: string; uri: string; secret: string } }> = ({
  enrollment,
}) => {
  const form = useForm({ code: "" });
  const errors = fieldErrors(form.errors);
  const [showSecret, setShowSecret] = React.useState(false);

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle className="text-sm">1. Ponha a conta no autenticador</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-sm text-muted-foreground">
            Escaneie o QR Code com o aplicativo autenticador. Quem está nesta
            página pelo próprio celular não consegue apontar a câmera para a
            tela — nesse caso use o botão abaixo, que abre o aplicativo já com a
            conta preenchida.
          </p>

          {/* Sempre visível: é o caminho principal, e esconder atrás de um
              toggle fazia parecer que o QR Code nem existia.
              Fundo branco fixo: o QR precisa de contraste alto para ser lido,
              inclusive no tema escuro. */}
          {/* A placa branca abraça o QR em vez de atravessar o cartão: o
              branco é obrigatório (leitor de QR precisa do contraste), mas no
              tema escuro uma faixa branca de ponta a ponta ofusca. */}
          <div className="flex justify-center">
            <div className="rounded-xl border border-border bg-white p-3">
              <img
                src={enrollment.qrCode}
                alt="QR Code para o aplicativo autenticador"
                className="size-44"
              />
            </div>
          </div>

          {/* `otpauth://` é o mesmo conteúdo do QR Code. O esquema é registrado
              pelos autenticadores (Google, Authy, 1Password, Microsoft), então
              tocar aqui no celular abre o aplicativo direto. */}
          {/* Continua em tamanho cheio: é o alvo de toque de quem está no
              celular, onde a câmera não serve. */}
          <Button asChild size="lg" className="w-full">
            <a href={enrollment.uri}>
              <Smartphone className="size-4" />
              Abrir no aplicativo autenticador
            </a>
          </Button>

          <button
            type="button"
            onClick={() => setShowSecret(!showSecret)}
            className="w-full text-center text-xs text-muted-foreground underline underline-offset-4"
          >
            Digitar a chave manualmente
          </button>

          {showSecret && <SecretKey secret={enrollment.secret} />}

          {/* Trocar o QR invalida o que já foi escaneado, então fica atrás de
              uma confirmação — é o caminho de quem leu no aplicativo errado. */}
          <AlertDialog>
            <AlertDialogTrigger asChild>
              <button
                type="button"
                className="w-full text-center text-xs text-muted-foreground underline underline-offset-4"
              >
                Gerar outro QR Code
              </button>
            </AlertDialogTrigger>

            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>Gerar um QR Code novo?</AlertDialogTitle>
                <AlertDialogDescription>
                  O código que você já escaneou deixa de valer, e será preciso
                  escanear de novo. Use só se o aplicativo não ficou com a conta.
                </AlertDialogDescription>
              </AlertDialogHeader>

              <AlertDialogFooter>
                <AlertDialogCancel>Voltar</AlertDialogCancel>
                <AlertDialogAction onClick={() => router.post("/seguranca/2fa")}>
                  Gerar outro
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm">2. Confirme com o primeiro código</CardTitle>
        </CardHeader>
        <CardContent>
          <form
            className="space-y-4"
            onSubmit={(event) => {
              event.preventDefault();
              form.post("/seguranca/2fa/confirmar");
            }}
          >
            <Field label="Código de 6 dígitos" htmlFor="code" error={errors.code}>
              <Input
                id="code"
                inputMode="numeric"
                autoComplete="one-time-code"
                autoFocus
                required
                maxLength={6}
                placeholder="000000"
                className="text-center text-2xl tracking-[0.4em] tabular-nums"
                value={form.data.code}
                onChange={(event) => form.setData("code", event.target.value)}
                aria-invalid={Boolean(errors.code)}
              />
            </Field>

            <Button type="submit" size="sm" className="w-full" disabled={form.processing}>
              {form.processing ? "Conferindo..." : "Confirmar e ativar"}
            </Button>
          </form>
        </CardContent>
      </Card>
    </>
  );
};

const SecretKey: React.FC<{ secret: string }> = ({ secret }) => {
  const [copied, setCopied] = React.useState(false);

  // Agrupado de 4 em 4 para conferir dígito a dígito sem perder o lugar.
  const grouped = secret.match(/.{1,4}/g)?.join(" ") ?? secret;

  return (
    <div className="flex items-center gap-2 rounded-lg border border-border bg-muted p-3">
      <code className="flex-1 break-all font-mono text-sm">{grouped}</code>
      <Button
        variant="ghost"
        size="icon"
        aria-label="Copiar chave"
        onClick={() => {
          navigator.clipboard?.writeText(secret);
          setCopied(true);
          setTimeout(() => setCopied(false), 2000);
        }}
      >
        {copied ? <Check className="size-4" /> : <Copy className="size-4" />}
      </Button>
    </div>
  );
};

const RecoveryCodes: React.FC<{ codes: string[] }> = ({ codes }) => (
  <Card>
    <CardHeader>
      <CardTitle className="flex items-center gap-2 text-sm">
        <ShieldCheck className="size-4 text-success" />
        Guarde os códigos de recuperação
      </CardTitle>
    </CardHeader>
    <CardContent className="space-y-4">
      <p className="text-sm text-muted-foreground">
        Se você perder o celular, é com um destes que consegue entrar. Cada um serve
        uma vez só. <strong className="text-foreground">Eles não aparecem de novo</strong> —
        anote agora.
      </p>

      <ul className="grid grid-cols-2 gap-2">
        {codes.map((code) => (
          <li
            key={code}
            className="rounded-lg border border-border bg-muted px-3 py-2 text-center font-mono text-sm"
          >
            {code}
          </li>
        ))}
      </ul>

      <Button
        variant="outline"
        size="sm"
        className="w-full"
        onClick={() => navigator.clipboard?.writeText(codes.join("\n"))}
      >
        <Copy className="size-4" />
        Copiar todos
      </Button>

      <Button size="sm" className="w-full" onClick={() => router.get("/seguranca")}>
        Anotei, pode continuar
      </Button>
    </CardContent>
  </Card>
);

const Enabled: React.FC<{ twoFactor: Props["twoFactor"] }> = ({ twoFactor }) => (
  <Card>
    <CardHeader className="flex-row items-center justify-between">
      <CardTitle className="flex items-center gap-2 text-sm">
        <ShieldCheck className="size-4 text-success" />
        Verificação em duas etapas
      </CardTitle>
      <Badge>ativa</Badge>
    </CardHeader>

    <CardContent className="space-y-4">
      <dl className="space-y-1 text-sm">
        <div className="flex justify-between">
          <dt className="text-muted-foreground">Ativada em</dt>
          <dd>{twoFactor.confirmedAt ? dateTimeLabel(twoFactor.confirmedAt) : "—"}</dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-muted-foreground">Códigos de recuperação</dt>
          <dd className={twoFactor.recoveryCodesLeft <= 2 ? "text-warning-foreground" : ""}>
            {twoFactor.recoveryCodesLeft} restantes
          </dd>
        </div>
      </dl>

      {twoFactor.recoveryCodesLeft <= 2 && (
        <p className="rounded-lg border border-warning/30 bg-warning/10 p-3 text-xs text-warning-foreground">
          Poucos códigos de recuperação. Desligue e ligue a verificação para gerar
          oito novos.
        </p>
      )}

      <AlertDialog>
        <AlertDialogTrigger asChild>
          <Button variant="outline" size="sm" className="w-full text-destructive">
            <ShieldOff className="size-4" />
            Desligar verificação
          </Button>
        </AlertDialogTrigger>

        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Desligar a verificação em duas etapas?</AlertDialogTitle>
            <AlertDialogDescription>
              Os códigos de recuperação atuais deixam de valer. Como a
              verificação é obrigatória, você precisará ativá-la de novo — com
              outro QR Code — para voltar a usar o sistema.
            </AlertDialogDescription>
          </AlertDialogHeader>

          <AlertDialogFooter>
            <AlertDialogCancel>Manter ligada</AlertDialogCancel>
            <AlertDialogAction onClick={() => router.post("/seguranca/2fa/desligar")}>
              Desligar
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </CardContent>
  </Card>
);
