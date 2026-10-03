import * as React from "react";
import { useForm } from "@inertiajs/react";
import { Trash2 } from "lucide-react";
import { AppLayout } from "@/layouts/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input, Textarea } from "@/components/ui/input";
import { MoneyInput } from "@/components/ui/money-input";
import { Field } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { AddressPicker } from "@/components/AddressPicker";
import { PaymentFields } from "@/components/PaymentFields";
import { ProductPicker, previewDiscount, type CartItem } from "@/components/ProductPicker";
import { toast } from "@/components/ui/sonner";
import { dateLabel, money, parseNumber, unitPrice, weight } from "@/lib/format";
import { fieldErrors } from "@/lib/errors";
import type { DiscountType, Driver, Product, Unit } from "@/types";

// O Radix não aceita `value=""` num item de Select (string vazia é o estado
// "sem seleção"), então "sem entregador" precisa de um valor próprio.
const UNASSIGNED = "sem-entregador";

type Props = {
  products: Product[];
  /** Entregadores ativos, para a venda já sair com dono. */
  drivers: Driver[];
  /** Hoje no fuso da loja: o vencimento da venda a prazo parte daqui. */
  today: string;
};

export default function NewOrder({ products, drivers, today }: Props) {
  const [cart, setCart] = React.useState<CartItem[]>([]);

  const form = useForm({
    items: [] as { product_id: string; batch_id: string; quantity: string; unit: Unit }[],
    customer_name: "",
    note: "",
    discount_type: "none" as DiscountType,
    discount_value: "",
    // Entrega ligada por padrão: é o fluxo comum. Desligar marca o pedido
    // como retirada e o tira da fila de entrega.
    needs_delivery: true,
    delivery_address: "",
    // Vazio quer dizer "decide depois": o pedido entra na fila sem dono e
    // alguém despacha da tela do pedido.
    driver_id: "",
    // Coordenadas do endereço escolhido no mapa. Vão como texto porque é
    // assim que o formulário viaja; o servidor converte para decimal.
    delivery_lat: "",
    delivery_lon: "",
    // À vista por padrão: é o fluxo comum. A prazo leva o dia combinado com
    // o cliente, e o pedido fica em aberto até alguém dar baixa.
    on_credit: false,
    payment_due_on: "",
  });
  const { data, setData, post, processing } = form;
  const errors = fieldErrors(form.errors);

  const subtotal = cart.reduce((acc, item) => acc + item.total, 0);
  const discount = previewDiscount(subtotal, data.discount_type, data.discount_value);
  const total = Math.max(subtotal - discount, 0);

  const addItem = (item: CartItem) => {
    // Mesmo lote duas vezes vira uma linha só — é o que o servidor faz ao
    // validar o estoque, então a tela precisa mostrar o mesmo. Lotes
    // diferentes ficam separados: custaram preços diferentes.
    const next = [...cart];
    const existing = next.findIndex((entry) => entry.batchId === item.batchId);

    if (existing >= 0) {
      const grams = next[existing].grams + item.grams;
      next[existing] = { ...next[existing], grams, total: grams * item.pricePerGram };
    } else {
      next.push(item);
    }

    setCart(next);
    syncItems(next);
  };

  const removeItem = (batchId: string) => {
    const next = cart.filter((item) => item.batchId !== batchId);
    setCart(next);
    syncItems(next);
  };

  // O carrinho é a fonte da verdade da tela; `data.items` é só o que vai no
  // POST — em gramas, para o servidor não precisar refazer a conversão.
  const syncItems = (items: CartItem[]) =>
    setData(
      "items",
      items.map((item) => ({
        product_id: item.productId,
        batch_id: item.batchId,
        quantity: String(item.grams),
        unit: "g" as Unit,
      })),
    );

  const submit = (event: React.FormEvent) => {
    event.preventDefault();

    if (cart.length === 0) {
      toast.error("Adicione ao menos um produto ao pedido.");
      return;
    }

    if (data.on_credit && data.payment_due_on === "") {
      toast.error("Escolha o dia do pagamento da venda a prazo.");
      return;
    }

    post("/pedidos");
  };

  return (
    <AppLayout title="Novo pedido" back="/pedidos">
      <form className="space-y-4" onSubmit={submit}>
        <ProductPicker products={products} onAdd={addItem} />

        <Card>
          <CardHeader>
            <CardTitle className="text-sm">
              Itens {cart.length > 0 && `(${cart.length})`}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {cart.length === 0 ? (
              <p className="py-6 text-center text-sm text-muted-foreground">
                Nenhum item ainda. Escolha um produto acima.
              </p>
            ) : (
              <ul className="divide-y divide-border">
                {cart.map((item) => (
                  <li key={item.batchId} className="flex items-center gap-3 py-3">
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium">{item.name}</p>
                      <p className="truncate text-xs text-muted-foreground">
                        {weight(item.grams)} × {unitPrice(item.pricePerGram)}/g ·{" "}
                        {item.batchLabel}
                      </p>
                    </div>

                    <span className="shrink-0 text-sm font-semibold tabular-nums">
                      {money(item.total)}
                    </span>

                    <Button
                      variant="ghost"
                      size="icon"
                      className="shrink-0 text-muted-foreground hover:text-destructive"
                      onClick={() => removeItem(item.batchId)}
                      aria-label={`Remover ${item.name}`}
                    >
                      <Trash2 className="size-4" />
                    </Button>
                  </li>
                ))}
              </ul>
            )}

            {errors.items && (
              <p className="pt-2 text-sm font-medium text-destructive">{errors.items}</p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm">Desconto</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div role="group" aria-label="Tipo de desconto" className="grid grid-cols-3 gap-1 rounded-lg bg-muted p-1">
              {(
                [
                  ["none", "Sem desconto"],
                  ["percent", "%"],
                  ["amount", "R$"],
                ] as const
              ).map(([value, label]) => (
                <button
                  key={value}
                  type="button"
                  onClick={() =>
                    // Trocar % por R$ zera o campo: "10" quer dizer coisas
                    // muito diferentes nos dois, e aproveitar o número
                    // anterior daria um desconto que ninguém pediu.
                    setData((current) => ({
                      ...current,
                      discount_type: value,
                      discount_value: "",
                    }))
                  }
                  aria-pressed={data.discount_type === value}
                  className={
                    data.discount_type === value
                      ? "h-9 rounded-md bg-card text-sm font-medium shadow-sm"
                      : "h-9 rounded-md text-sm font-medium text-muted-foreground"
                  }
                >
                  {label}
                </button>
              ))}
            </div>

            {data.discount_type !== "none" && (
              <Field
                label={data.discount_type === "percent" ? "Porcentagem" : "Valor em reais"}
                htmlFor="discount_value"
                error={errors.discount_value}
              >
                {data.discount_type === "amount" ? (
                  <MoneyInput
                    id="discount_value"
                    value={data.discount_value}
                    onChange={(value) => setData("discount_value", value)}
                  />
                ) : (
                  <Input
                    id="discount_value"
                    inputMode="decimal"
                    placeholder="10"
                    value={data.discount_value}
                    onChange={(e) => setData("discount_value", e.target.value)}
                  />
                )}
              </Field>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm">Pagamento</CardTitle>
          </CardHeader>
          <CardContent>
            <PaymentFields
              today={today}
              onCredit={data.on_credit}
              dueOn={data.payment_due_on}
              error={errors.payment_due_on}
              onCreditChange={(value) => setData("on_credit", value)}
              onDueOnChange={(value) => setData("payment_due_on", value)}
            />
          </CardContent>
        </Card>

        <Card>
          <CardContent className="space-y-4 p-4">
            <Field
              label="Cliente"
              htmlFor="customer_name"
              hint={data.on_credit ? "Obrigatório na venda a prazo: é quem vai pagar." : "Opcional."}
              error={errors.customer_name}
            >
              <Input
                id="customer_name"
                value={data.customer_name}
                onChange={(e) => setData("customer_name", e.target.value)}
                placeholder="Nome de quem está comprando"
              />
            </Field>

            <Field label="Observação" htmlFor="note" hint="Opcional.">
              <Textarea
                id="note"
                rows={2}
                value={data.note}
                onChange={(e) => setData("note", e.target.value)}
              />
            </Field>

            <label className="flex items-center justify-between gap-3 pt-1">
              <span className="space-y-0.5">
                <span className="block text-sm font-medium">Vai ser entregue</span>
                <span className="block text-xs text-muted-foreground">
                  Desligue para retirada no balcão — assim o pedido não entra na
                  fila de entrega.
                </span>
              </span>
              <Switch
                checked={data.needs_delivery}
                onCheckedChange={(checked) => setData("needs_delivery", checked)}
              />
            </label>

            {/* Endereço e entregador só existem quando há entrega: numa
                retirada seriam perguntas sem resposta. */}
            {data.needs_delivery && (
              <div className="space-y-4 border-t border-border pt-4">
                {/* O campo existe mesmo sem entregador cadastrado: escondê-lo
                    faria a venda parecer não ter essa escolha, quando o que
                    falta é gente na equipe. */}
                <Field
                  label="Entregador"
                  htmlFor="driver_id"
                  hint={
                    drivers.length > 0
                      ? "Opcional. Em branco, o pedido entra na fila e você escolhe depois, na tela do pedido."
                      : "Nenhum entregador ativo na equipe. O pedido entra na fila e espera — quem cadastra entregador é o administrador, em Equipe."
                  }
                  error={errors.driver_id}
                >
                  <Select
                    value={data.driver_id}
                    disabled={drivers.length === 0}
                    onValueChange={(value) =>
                      setData("driver_id", value === UNASSIGNED ? "" : value)
                    }
                  >
                    <SelectTrigger id="driver_id" aria-label="Entregador">
                      <SelectValue
                        placeholder={
                          drivers.length > 0 ? "Definir depois" : "Nenhum entregador cadastrado"
                        }
                      />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value={UNASSIGNED}>Definir depois</SelectItem>
                      {drivers.map((driver) => (
                        <SelectItem key={driver.id} value={driver.id}>
                          {driver.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </Field>

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
              </div>
            )}
          </CardContent>
        </Card>

        {/* Resumo fixo acima da barra de navegação: no celular, o total tem de
            estar sempre visível enquanto se monta o pedido. */}
        <div className="sticky bottom-16 z-20 rounded-xl border border-border bg-card p-4 shadow-lg">
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
            {data.on_credit && (
              <div className="flex justify-between text-muted-foreground">
                <dt>A prazo</dt>
                <dd className="tabular-nums">
                  {data.payment_due_on === ""
                    ? "escolha o dia"
                    : `vence ${dateLabel(data.payment_due_on)}`}
                </dd>
              </div>
            )}
          </dl>

          <Button
            type="submit"
            size="lg"
            className="mt-3 w-full"
            disabled={processing || cart.length === 0}
          >
            {processing ? "Registrando..." : "Registrar pedido"}
          </Button>
        </div>
      </form>
    </AppLayout>
  );
}
