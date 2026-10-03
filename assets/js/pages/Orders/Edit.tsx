import * as React from "react";
import { useForm } from "@inertiajs/react";
import { Trash2 } from "lucide-react";
import { AppLayout } from "@/layouts/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input, Textarea } from "@/components/ui/input";
import { Field } from "@/components/ui/label";
import { toast } from "@/components/ui/sonner";
import { AddressPicker } from "@/components/AddressPicker";
import { PaymentFields } from "@/components/PaymentFields";
import { ProductPicker, previewDiscount, type CartItem } from "@/components/ProductPicker";
import { UnitToggle } from "@/components/UnitToggle";
import { fieldErrors } from "@/lib/errors";
import {
  dateLabel,
  dateTimeLabel,
  money,
  parseNumber,
  toGrams,
  unitPrice,
  weight,
} from "@/lib/format";
import type { Order, OrderItem, Product, Unit } from "@/types";

type Props = {
  order: Order;
  /** Produtos com lote em aberto, para incluir linha nova. */
  products: Product[];
  /** Hoje no fuso da loja: um vencimento novo parte daqui. */
  today: string;
};

/**
 * Linha do pedido em edição. `id` existe na linha que já estava no pedido:
 * ela guarda o lote, o preço e o custo da venda, e só o peso muda. Linha sem
 * `id` é nova, com o preço de agora.
 */
type Line = {
  key: string;
  id: string | null;
  productId: string;
  batchId: string | null;
  name: string;
  batchLabel: string | null;
  quantity: string;
  unit: Unit;
  pricePerGram: number;
};

/** Peso como a pessoa leria: 1500g aparece como "1,5" kg. */
function quantityIn(grams: number, unit: Unit): string {
  const value = unit === "kg" ? grams / 1000 : grams;
  return String(Number(value.toFixed(3))).replace(".", ",");
}

const gramsOf = (line: Line) => toGrams(parseNumber(line.quantity) ?? 0, line.unit);

function fromItem(item: OrderItem): Line {
  const unit: Unit = item.grams >= 1000 ? "kg" : "g";

  return {
    key: item.id,
    id: item.id,
    productId: item.productId,
    batchId: item.batchId,
    name: item.productName,
    batchLabel: item.batchLabel,
    quantity: quantityIn(item.grams, unit),
    unit,
    pricePerGram: item.pricePerGram,
  };
}

/**
 * Editar o pedido: dados do cliente, entrega, pagamento e os itens.
 *
 * Os itens mexem no estoque de verdade — peso a mais sai do lote, peso a
 * menos e linha removida voltam ao mesmo lote —, mas só quando a pessoa
 * salva, e tudo de uma vez. Linha que já estava mantém o preço da venda;
 * linha nova entra com o preço de agora. O desconto continua o mesmo,
 * refeito sobre o novo subtotal pelo servidor (o resumo aqui é só prévia).
 *
 * Quem editou e o que havia antes ficam no log de auditoria, que é do admin.
 */
export default function OrderEdit({ order, products, today }: Props) {
  const delivery = order.deliveryStatus !== "not_required";
  const paid = order.paidAt !== null;

  const originals = React.useMemo(() => (order.items ?? []).map(fromItem), [order.items]);
  const [lines, setLines] = React.useState<Line[]>(originals);

  const form = useForm({
    customer_name: order.customerName ?? "",
    note: order.note ?? "",
    delivery_address: order.deliveryAddress ?? "",
    delivery_lat: order.deliveryLat === null ? "" : String(order.deliveryLat),
    delivery_lon: order.deliveryLon === null ? "" : String(order.deliveryLon),
    on_credit: order.paymentDueOn !== null,
    payment_due_on: order.paymentDueOn ?? "",
  });
  const { data, setData, put, processing } = form;
  const errors = fieldErrors(form.errors);

  const subtotal = lines.reduce((acc, line) => acc + gramsOf(line) * line.pricePerGram, 0);
  const discount = previewDiscount(subtotal, order.discountType, String(order.discountValue));
  const total = Math.max(subtotal - discount, 0);

  const updateLine = (key: string, changes: Partial<Line>) =>
    setLines((current) =>
      current.map((line) => (line.key === key ? { ...line, ...changes } : line)),
    );

  /**
   * O mesmo lote nunca vira duas linhas — é o que o servidor faz. Lote que
   * já está na lista soma na linha dele; lote de uma linha que a pessoa tirou
   * nesta edição volta a ser aquela linha, com o preço da venda.
   */
  const addItem = (item: CartItem) => {
    const current = lines.find((line) => line.batchId === item.batchId);

    if (current) {
      updateLine(current.key, {
        quantity: quantityIn(gramsOf(current) + item.grams, current.unit),
      });
      return;
    }

    const original = originals.find((line) => line.batchId === item.batchId);
    const unit: Unit = item.grams >= 1000 ? "kg" : "g";

    setLines([
      ...lines,
      original
        ? { ...original, quantity: quantityIn(item.grams, original.unit) }
        : {
            key: item.batchId,
            id: null,
            productId: item.productId,
            batchId: item.batchId,
            name: item.name,
            batchLabel: item.batchLabel,
            quantity: quantityIn(item.grams, unit),
            unit,
            pricePerGram: item.pricePerGram,
          },
    ]);
  };

  const submit = (event: React.FormEvent) => {
    event.preventDefault();

    if (!paid) {
      if (lines.length === 0) {
        toast.error("O pedido precisa de ao menos um item.");
        return;
      }

      if (lines.some((line) => gramsOf(line) <= 0)) {
        toast.error("Informe um peso válido para cada item.");
        return;
      }

      if (data.on_credit && data.payment_due_on === "") {
        toast.error("Escolha o dia do pagamento da venda a prazo.");
        return;
      }
    }

    // Os itens vão em gramas, como no registro — o servidor não refaz a
    // conversão. Conta paga não manda itens: eles não mudam mais.
    form.transform((current) => ({
      ...current,
      ...(paid
        ? {}
        : {
            items: lines.map((line) =>
              line.id
                ? { id: line.id, quantity: String(gramsOf(line)), unit: "g" }
                : {
                    product_id: line.productId,
                    batch_id: line.batchId,
                    quantity: String(gramsOf(line)),
                    unit: "g",
                  },
            ),
          }),
    }));

    put(`/pedidos/${order.id}`);
  };

  return (
    <AppLayout title={`Editar pedido ${order.code}`} back={`/pedidos/${order.id}`}>
      <form className="space-y-4" onSubmit={submit}>
        {paid ? (
          <Card>
            <CardHeader>
              <CardTitle className="text-sm">Itens</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <ul className="divide-y divide-border">
                {originals.map((line) => (
                  <li key={line.key} className="flex justify-between gap-3 py-2 text-sm">
                    <span className="truncate">{line.name}</span>
                    <span className="shrink-0 tabular-nums text-muted-foreground">
                      {weight(gramsOf(line))}
                    </span>
                  </li>
                ))}
              </ul>
              <p className="text-xs text-muted-foreground">
                O pagamento já foi registrado: os itens não mudam mais, para não reescrever
                quanto foi recebido.
              </p>
            </CardContent>
          </Card>
        ) : (
          <>
            <Card>
              <CardHeader>
                <CardTitle className="text-sm">Itens ({lines.length})</CardTitle>
              </CardHeader>
              <CardContent>
                {lines.length === 0 ? (
                  <p className="py-6 text-center text-sm text-muted-foreground">
                    Nenhum item. Inclua um produto abaixo.
                  </p>
                ) : (
                  <ul className="divide-y divide-border">
                    {lines.map((line) => (
                      <li key={line.key} className="space-y-2 py-3">
                        <div className="flex items-start gap-3">
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-sm font-medium">{line.name}</p>
                            <p className="truncate text-xs text-muted-foreground">
                              {unitPrice(line.pricePerGram)}/g
                              {line.batchLabel ? ` · ${line.batchLabel}` : ""}
                              {line.id ? "" : " · novo"}
                            </p>
                          </div>

                          <span className="shrink-0 text-sm font-semibold tabular-nums">
                            {money(gramsOf(line) * line.pricePerGram)}
                          </span>

                          <Button
                            variant="ghost"
                            size="icon"
                            className="-mt-2 shrink-0 text-muted-foreground hover:text-destructive"
                            onClick={() =>
                              setLines(lines.filter((entry) => entry.key !== line.key))
                            }
                            aria-label={`Remover ${line.name}`}
                          >
                            <Trash2 className="size-4" />
                          </Button>
                        </div>

                        <div className="grid grid-cols-[1fr_auto] gap-2">
                          <Input
                            inputMode="decimal"
                            aria-label={`Peso de ${line.name}`}
                            value={line.quantity}
                            onChange={(e) => updateLine(line.key, { quantity: e.target.value })}
                            aria-invalid={gramsOf(line) <= 0}
                          />
                          {/* Trocar a unidade converte o que está digitado:
                              1,5 kg vira 1500 g, não 1,5 g. */}
                          <UnitToggle
                            value={line.unit}
                            onChange={(unit) =>
                              updateLine(line.key, {
                                unit,
                                quantity: quantityIn(gramsOf(line), unit),
                              })
                            }
                          />
                        </div>
                      </li>
                    ))}
                  </ul>
                )}

                {errors.items && (
                  <p className="pt-2 text-sm font-medium text-destructive">{errors.items}</p>
                )}
              </CardContent>
            </Card>

            <ProductPicker products={products} onAdd={addItem} />
          </>
        )}

        <Card>
          <CardContent className="space-y-4 p-4">
            <Field
              label="Cliente"
              htmlFor="customer_name"
              hint={
                data.on_credit && !paid
                  ? "Obrigatório na venda a prazo: é quem vai pagar."
                  : "Opcional."
              }
              error={errors.customer_name}
            >
              <Input
                id="customer_name"
                value={data.customer_name}
                onChange={(e) => setData("customer_name", e.target.value)}
                placeholder="Nome de quem está comprando"
              />
            </Field>

            <Field label="Observação" htmlFor="note" hint="Opcional." error={errors.note}>
              <Textarea
                id="note"
                rows={2}
                value={data.note}
                onChange={(e) => setData("note", e.target.value)}
              />
            </Field>
          </CardContent>
        </Card>

        {delivery && (
          <Card>
            <CardHeader>
              <CardTitle className="text-sm">Entrega</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <AddressPicker
                address={data.delivery_address}
                lat={parseNumber(data.delivery_lat)}
                lon={parseNumber(data.delivery_lon)}
                onChange={({ address, lat, lon }) =>
                  setData((current) => ({
                    ...current,
                    delivery_address: address,
                    delivery_lat: lat === null ? "" : String(lat),
                    delivery_lon: lon === null ? "" : String(lon),
                  }))
                }
              />
              {errors.delivery_address && (
                <p className="text-xs font-medium text-destructive">{errors.delivery_address}</p>
              )}
            </CardContent>
          </Card>
        )}

        <Card>
          <CardHeader>
            <CardTitle className="text-sm">Pagamento</CardTitle>
          </CardHeader>
          <CardContent>
            {/* Depois da baixa a forma de pagamento é história: trocar o
                vencimento de uma conta paga reescreveria se ela foi paga em
                dia. */}
            {paid ? (
              <p className="text-sm text-muted-foreground">
                A prazo, vencia em {dateLabel(order.paymentDueOn ?? "")}, pago em{" "}
                {dateTimeLabel(order.paidAt ?? "")}. A forma de pagamento não muda mais.
              </p>
            ) : (
              <PaymentFields
                today={today}
                onCredit={data.on_credit}
                dueOn={data.payment_due_on}
                error={errors.payment_due_on}
                onCreditChange={(value) => setData("on_credit", value)}
                onDueOnChange={(value) => setData("payment_due_on", value)}
              />
            )}
          </CardContent>
        </Card>

        {errors.form && <p className="text-sm font-medium text-destructive">{errors.form}</p>}

        {/* Resumo fixo como no registro: mexendo nos itens, o total novo tem
            de estar à vista antes de salvar. */}
        <div className="sticky bottom-16 z-20 rounded-xl border border-border bg-card p-4 shadow-lg">
          {!paid && (
            <dl className="space-y-1 text-sm">
              <div className="flex justify-between text-muted-foreground">
                <dt>Subtotal</dt>
                <dd className="tabular-nums">{money(subtotal)}</dd>
              </div>
              {discount > 0 && (
                <div className="flex justify-between text-muted-foreground">
                  <dt>Desconto</dt>
                  <dd className="tabular-nums">- {money(discount)}</dd>
                </div>
              )}
              <div className="flex justify-between border-t border-border pt-1 text-base font-semibold">
                <dt>Total</dt>
                <dd className="tabular-nums">{money(total)}</dd>
              </div>
              {Math.abs(total - order.total) >= 0.005 && (
                <div className="flex justify-between text-xs text-muted-foreground">
                  <dt>Antes</dt>
                  <dd className="tabular-nums">{money(order.total)}</dd>
                </div>
              )}
            </dl>
          )}

          <Button
            type="submit"
            size="lg"
            className={paid ? "w-full" : "mt-3 w-full"}
            disabled={processing}
          >
            {processing ? "Salvando..." : "Salvar alterações"}
          </Button>
        </div>
      </form>
    </AppLayout>
  );
}
