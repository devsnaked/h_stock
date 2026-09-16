import * as React from "react";
import { Link, router, useForm } from "@inertiajs/react";
import {
  ArrowDownRight,
  ArrowUpRight,
  Coins,
  Layers,
  Minus,
  Pencil,
  PackagePlus,
  Scale,
} from "lucide-react";
import { AppLayout } from "@/layouts/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input, Textarea } from "@/components/ui/input";
import { MoneyInput } from "@/components/ui/money-input";
import { Field } from "@/components/ui/label";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { UnitToggle } from "@/components/UnitToggle";
import { Collapsible } from "@/components/ui/collapsible";
import { Pagination, type Page } from "@/components/Pagination";
import { useAuth } from "@/hooks/useAuth";
import {
  dateTimeLabel,
  money,
  moneyInput,
  parseNumber,
  priceIn,
  toGrams,
  unitLabel,
  unitPrice,
  weight,
} from "@/lib/format";
import { fieldErrors } from "@/lib/errors";
import type { Batch, MovementKind, Product, StockMovement, Unit } from "@/types";

type Props = {
  product: Product;
  batches: Batch[];
  movements: StockMovement[];
  /** Recorte do histórico — ele é paginado, os lotes não. */
  movementsPage: Page;
  /** Quem alcança pedido de outra pessoa vê o histórico com link. */
  canOpenOrders: boolean;
};

const KIND_LABEL: Record<MovementKind, string> = {
  in: "Entrada",
  out: "Saída",
  adjustment: "Ajuste",
};

export default function ProductShow({
  product,
  batches,
  movements,
  movementsPage,
  canOpenOrders,
}: Props) {
  const { managesStock } = useAuth();
  const open = batches.filter((batch) => !batch.depleted);
  const depleted = batches.filter((batch) => batch.depleted);

  return (
    <AppLayout
      title={product.name}
      subtitle={`${unitPrice(priceIn(product.pricePerGram, product.unit))} / ${unitLabel(product.unit)}`}
      back="/produtos"
    >
      <div className="space-y-4">
        <Card>
          <CardContent className="space-y-4 p-4">
            <div className="flex items-end justify-between gap-3">
              <div>
                <p className="text-xs text-muted-foreground">Em estoque</p>
                <p className="text-3xl font-semibold tabular-nums">
                  {weight(product.stockGrams)}
                </p>
              </div>

              <div className="flex flex-col items-end gap-1">
                {!product.active && <Badge variant="outline">inativo</Badge>}
                {product.lowStock && <Badge variant="warning">estoque baixo</Badge>}
              </div>
            </div>

            <dl className="grid grid-cols-2 gap-3 border-t border-border pt-3 text-sm">
              <Detail label="Preço por grama" value={unitPrice(product.pricePerGram)} />
              <Detail label="Preço por kg" value={money(product.pricePerKg)} />
              <Detail label="Estoque mínimo" value={weight(product.minStockGrams)} />
              <Detail label="Unidade" value={unitLabel(product.unit)} />
              {product.stockCostValue !== undefined && (
                <Detail
                  label="Custo do que há em estoque"
                  value={money(product.stockCostValue)}
                />
              )}
            </dl>

            {managesStock && (
              <div className="flex gap-2 pt-1">
                <EntryDialog product={product} />
                <Button asChild variant="outline" size="icon" aria-label="Editar produto">
                  <Link href={`/produtos/${product.id}/editar`}>
                    <Pencil className="size-4" />
                  </Link>
                </Button>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <Layers className="size-4 text-muted-foreground" />
              Lotes {open.length > 0 && `(${open.length})`}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {open.length === 0 ? (
              <p className="py-6 text-center text-sm text-muted-foreground">
                Nenhum lote com saldo. Dê entrada de mercadoria para começar.
              </p>
            ) : (
              open.map((batch) => (
                <BatchRow
                  key={batch.id}
                  product={product}
                  batch={batch}
                  managesStock={managesStock}
                />
              ))
            )}

            {depleted.length > 0 && (
              <Collapsible
                className="pt-1"
                label={`${depleted.length} ${depleted.length === 1 ? "lote acabado" : "lotes acabados"}`}
              >
                <div className="space-y-2">
                  {depleted.map((batch) => (
                    <BatchRow
                      key={batch.id}
                      product={product}
                      batch={batch}
                      managesStock={managesStock}
                    />
                  ))}
                </div>
              </Collapsible>
            )}
          </CardContent>
        </Card>

        {managesStock && (
          <Card>
            <CardHeader>
              <CardTitle className="text-sm">Histórico</CardTitle>
            </CardHeader>
            <CardContent>
              {movements.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  Nenhuma movimentação registrada.
                </p>
              ) : (
                <ul className="divide-y divide-border">
                  {movements.map((movement) => {
                    const entrada = movement.grams >= 0;

                    return (
                      <li key={movement.id} className="flex items-start gap-3 py-3">
                        <span
                          className={
                            entrada
                              ? "mt-0.5 rounded-full bg-success/10 p-1.5 text-success"
                              : "mt-0.5 rounded-full bg-destructive/10 p-1.5 text-destructive"
                          }
                        >
                          {entrada ? (
                            <ArrowUpRight className="size-4" />
                          ) : (
                            <ArrowDownRight className="size-4" />
                          )}
                        </span>

                        <div className="min-w-0 flex-1">
                          <p className="text-sm font-medium">
                            {KIND_LABEL[movement.kind]} de {weight(Math.abs(movement.grams))}
                          </p>
                          <p className="truncate text-xs text-muted-foreground">
                            {movement.batchLabel ?? "sem lote"}
                            {movement.reason ? ` · ${movement.reason}` : ""}
                            {movement.userName ? ` · ${movement.userName}` : ""}
                          </p>
                          <p className="text-xs text-muted-foreground">
                            {dateTimeLabel(movement.insertedAt)}
                          </p>

                          {/* Toda saída de venda (e a devolução do
                              cancelamento) aponta para o pedido: é a resposta
                              de "para onde foram esses 500g?". Vira link só
                              para quem alcança pedido dos outros — do
                              contrário terminaria em "não encontrado". */}
                          {movement.orderCode &&
                            (canOpenOrders ? (
                              <Link
                                href={`/pedidos/${movement.orderId}`}
                                className="text-xs font-medium underline underline-offset-4"
                              >
                                Pedido {movement.orderCode}
                              </Link>
                            ) : (
                              <p className="text-xs text-muted-foreground">
                                Pedido {movement.orderCode}
                              </p>
                            ))}
                        </div>

                        <div className="shrink-0 text-right">
                          <p className="text-xs tabular-nums text-muted-foreground">
                            {weight(movement.balanceAfter)}
                          </p>
                          {movement.totalCost !== null && movement.totalCost !== 0 && (
                            <p className="text-xs tabular-nums text-muted-foreground">
                              {money(Math.abs(movement.totalCost))} em custo
                            </p>
                          )}
                        </div>
                      </li>
                    );
                  })}
                </ul>
              )}

              {/* Só o histórico é recarregado ao trocar de página: `only`
                  evita rebuscar produto e lotes, que não mudaram. */}
              <Pagination
                page={movementsPage}
                label="movimentação"
                onPage={(number) =>
                  router.get(
                    `/produtos/${product.id}`,
                    { historico: String(number) },
                    {
                      only: ["movements", "movementsPage"],
                      preserveState: true,
                      preserveScroll: true,
                      replace: true,
                    },
                  )
                }
              />
            </CardContent>
          </Card>
        )}
      </div>
    </AppLayout>
  );
}

const Detail: React.FC<{ label: string; value: string }> = ({ label, value }) => (
  <div>
    <dt className="text-xs text-muted-foreground">{label}</dt>
    <dd className="font-medium tabular-nums">{value}</dd>
  </div>
);

/**
 * Um lote na lista: o que ainda há dele, quanto custou e as duas coisas que
 * se faz com um lote — tirar mercadoria e corrigir o saldo.
 */
const BatchRow: React.FC<{ product: Product; batch: Batch; managesStock: boolean }> = ({
  product,
  batch,
  managesStock,
}) => (
  <div className="rounded-lg border border-border p-3">
    <div className="flex items-start justify-between gap-3">
      <div className="min-w-0">
        <p className="truncate text-sm font-medium">{batch.label}</p>
        <p className="text-xs text-muted-foreground">
          entrou {dateTimeLabel(batch.insertedAt)}
          {batch.userName ? ` · ${batch.userName}` : ""}
        </p>
      </div>

      <div className="shrink-0 text-right">
        <p className="text-sm font-semibold tabular-nums">{weight(batch.remainingGrams)}</p>
        {batch.costPerGram !== undefined && (
          <p className="text-xs tabular-nums text-muted-foreground">
            {unitPrice(priceIn(batch.costPerGram, product.unit))} / {unitLabel(product.unit)}
          </p>
        )}
      </div>
    </div>

    {batch.depleted ? (
      <p className="pt-2 text-xs text-muted-foreground">
        Acabado — entrou com {weight(batch.initialGrams)}.
      </p>
    ) : (
      managesStock && (
        <div className="flex gap-2 pt-3">
          <MovementDialog product={product} batch={batch} kind="out" />
          <MovementDialog product={product} batch={batch} kind="adjustment" />
          <CostDialog product={product} batch={batch} />
        </div>
      )
    )}
  </div>
);

/** Entrada de mercadoria: abre um lote, e por isso pede custo. */
const EntryDialog: React.FC<{ product: Product }> = ({ product }) => {
  const [open, setOpen] = React.useState(false);
  const [unit, setUnit] = React.useState<Unit>(product.unit);

  const form = useForm({
    kind: "in",
    batch_label: "",
    quantity: "",
    unit: product.unit as Unit,
    cost: "",
    reason: "",
  });

  const { data, setData, post, processing, reset } = form;
  const errors = fieldErrors(form.errors);

  const quantity = parseNumber(data.quantity);
  const cost = parseNumber(data.cost);
  const totalCost =
    quantity !== null && cost !== null && quantity > 0 && cost > 0 ? quantity * cost : null;

  // A unidade diz em que o peso é digitado, e com ele o que o custo
  // significa (por kg ou por grama). O dinheiro em si é sempre reais e
  // centavos, então o número digitado fica como está.
  const chooseUnit = (next: Unit) => {
    setUnit(next);
    setData("unit", next);
  };

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    post(`/produtos/${product.id}/estoque`, {
      onSuccess: () => {
        reset();
        setOpen(false);
      },
    });
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button className="flex-1">
          <PackagePlus className="size-4" />
          Entrada de mercadoria
        </Button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <DialogTitle>Nova entrada</DialogTitle>
          <DialogDescription>
            Cada entrada vira um lote com o custo dela. {product.name} · saldo atual{" "}
            {weight(product.stockGrams)}.
          </DialogDescription>
        </DialogHeader>

        <form className="space-y-4" onSubmit={submit}>
          <Field
            label="Lote"
            htmlFor="batch_label"
            error={errors.label}
            hint="Como você chama essa compra. Em branco vira a data de hoje."
          >
            <Input
              id="batch_label"
              autoFocus
              placeholder="Caixa do fornecedor, feira de terça..."
              value={data.batch_label}
              onChange={(e) => setData("batch_label", e.target.value)}
            />
          </Field>

          <Field label="Quantidade" htmlFor="quantity" error={errors.quantity ?? errors.grams}>
            <div className="space-y-2">
              <Input
                id="quantity"
                inputMode="decimal"
                required
                placeholder="0"
                value={data.quantity}
                onChange={(e) => setData("quantity", e.target.value)}
                aria-invalid={Boolean(errors.quantity ?? errors.grams)}
              />
              <UnitToggle value={unit} onChange={chooseUnit} />
            </div>
          </Field>

          <Field
            label={`Custo por ${unitLabel(unit)}`}
            htmlFor="cost"
            error={errors.cost ?? errors.cost_per_gram}
            hint={
              totalCost !== null
                ? `Total da compra: ${money(totalCost)}.`
                : "Quanto você pagou. É o que separa venda de lucro."
            }
          >
            <MoneyInput
              id="cost"
              required
              value={data.cost}
              onChange={(value) => setData("cost", value)}
              aria-invalid={Boolean(errors.cost ?? errors.cost_per_gram)}
            />
          </Field>

          <Field label="Motivo" htmlFor="reason" hint="Opcional, mas ajuda na auditoria.">
            <Textarea
              id="reason"
              rows={2}
              placeholder="Compra do fornecedor, reposição..."
              value={data.reason}
              onChange={(e) => setData("reason", e.target.value)}
            />
          </Field>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancelar</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>
              {processing ? "Salvando..." : "Registrar entrada"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};

/**
 * Correção do custo de um lote — inclusive o do estoque inicial, que só podia
 * ser digitado no cadastro do produto.
 *
 * É conserto de número, não movimentação: o peso não muda, e por isso não
 * aparece no histórico do produto (aparece no log de auditoria, com o antes e
 * o depois). Vale daqui para a frente: o que já foi vendido deste lote copiou
 * o custo dele para o item do pedido, e o lucro de um pedido fechado não se
 * reescreve.
 */
const CostDialog: React.FC<{ product: Product; batch: Batch }> = ({ product, batch }) => {
  const [open, setOpen] = React.useState(false);
  const [unit, setUnit] = React.useState<Unit>(product.unit);

  const atual = batch.costPerGram ?? 0;

  const form = useForm({
    unit: product.unit as Unit,
    cost: moneyInput(priceIn(atual, product.unit)),
    reason: "",
  });

  const { data, setData, post, processing, reset } = form;
  const errors = fieldErrors(form.errors);

  // Trocar a unidade converte o que está digitado: R$ 38,00/kg é R$ 0,04/g.
  const chooseUnit = (next: Unit) => {
    const digitado = parseNumber(data.cost);
    const porGrama = digitado === null ? null : unit === "kg" ? digitado / 1000 : digitado;

    setUnit(next);
    setData((current) => ({
      ...current,
      unit: next,
      cost: porGrama === null ? current.cost : moneyInput(priceIn(porGrama, next)),
    }));
  };

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    post(`/produtos/${product.id}/lotes/${batch.id}/custo`, {
      onSuccess: () => {
        reset();
        setOpen(false);
      },
    });
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm" className="flex-1">
          <Coins className="size-4" />
          Custo
        </Button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <DialogTitle>Corrigir o custo do lote</DialogTitle>
          <DialogDescription>
            {batch.label} · hoje a {unitPrice(priceIn(atual, product.unit))} por{" "}
            {unitLabel(product.unit)}.
          </DialogDescription>
        </DialogHeader>

        <form className="space-y-4" onSubmit={submit}>
          <Field
            label={`Custo por ${unitLabel(unit)}`}
            htmlFor={`cost-${batch.id}`}
            error={errors.cost ?? errors.cost_per_gram}
            hint="Vale para o que ainda vai sair deste lote. As vendas já registradas guardam o custo que tinham na hora."
          >
            <div className="space-y-2">
              <MoneyInput
                id={`cost-${batch.id}`}
                required
                value={data.cost}
                onChange={(value) => setData("cost", value)}
                aria-invalid={Boolean(errors.cost ?? errors.cost_per_gram)}
              />
              <UnitToggle value={unit} onChange={chooseUnit} />
            </div>
          </Field>

          <Field
            label="Motivo"
            htmlFor={`cost-reason-${batch.id}`}
            hint="Opcional, mas é o que explica a correção na auditoria."
          >
            <Textarea
              id={`cost-reason-${batch.id}`}
              rows={2}
              placeholder="Nota fiscal veio com outro valor..."
              value={data.reason}
              onChange={(e) => setData("reason", e.target.value)}
            />
          </Field>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancelar</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>
              {processing ? "Salvando..." : "Corrigir"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};

/**
 * Saída e ajuste de um lote. Não pedem custo: a mercadoria já entrou com o
 * dela, e é esse custo que sai junto.
 */
const MovementDialog: React.FC<{
  product: Product;
  batch: Batch;
  kind: Exclude<MovementKind, "in">;
}> = ({ product, batch, kind }) => {
  const [open, setOpen] = React.useState(false);
  const [unit, setUnit] = React.useState<Unit>(product.unit);

  const form = useForm({
    kind,
    batch_id: batch.id,
    quantity: "",
    unit: product.unit as Unit,
    reason: "",
  });

  const { data, setData, post, processing, reset } = form;
  const errors = fieldErrors(form.errors);

  const saida = kind === "out";
  const quantity = parseNumber(data.quantity);
  const excede = saida && quantity !== null && toGrams(quantity, unit) > batch.remainingGrams;

  const chooseUnit = (next: Unit) => {
    setUnit(next);
    setData("unit", next);
  };

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    post(`/produtos/${product.id}/estoque`, {
      onSuccess: () => {
        reset();
        setOpen(false);
      },
    });
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm" className="flex-1">
          {saida ? <Minus className="size-4" /> : <Scale className="size-4" />}
          {saida ? "Saída" : "Ajustar"}
        </Button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <DialogTitle>{saida ? "Saída do lote" : "Ajustar o lote"}</DialogTitle>
          <DialogDescription>
            {batch.label} · há {weight(batch.remainingGrams)} deste lote.
          </DialogDescription>
        </DialogHeader>

        <form className="space-y-4" onSubmit={submit}>
          <Field
            label={saida ? "Quantidade que saiu" : "Saldo correto do lote"}
            htmlFor={`quantity-${batch.id}`}
            error={errors.quantity ?? errors.grams ?? (excede ? "Mais do que há no lote." : undefined)}
            hint={
              saida
                ? undefined
                : "O sistema registra a diferença entre o saldo atual e este valor."
            }
          >
            <div className="space-y-2">
              <Input
                id={`quantity-${batch.id}`}
                inputMode="decimal"
                required
                autoFocus
                placeholder="0"
                value={data.quantity}
                onChange={(e) => setData("quantity", e.target.value)}
                aria-invalid={Boolean(errors.quantity ?? errors.grams) || excede}
              />
              <UnitToggle value={unit} onChange={chooseUnit} />
            </div>
          </Field>

          <Field label="Motivo" htmlFor={`reason-${batch.id}`} hint="Opcional, mas ajuda na auditoria.">
            <Textarea
              id={`reason-${batch.id}`}
              rows={2}
              placeholder={saida ? "Perda, uso interno..." : "Contagem, sobra na balança..."}
              value={data.reason}
              onChange={(e) => setData("reason", e.target.value)}
            />
          </Field>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancelar</Button>
            </DialogClose>
            <Button type="submit" disabled={processing || excede}>
              {processing ? "Salvando..." : "Confirmar"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};
