import * as React from "react";
import { useForm } from "@inertiajs/react";
import { Plus, Trash2 } from "lucide-react";
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
import { UnitToggle } from "@/components/UnitToggle";
import { AddressPicker } from "@/components/AddressPicker";
import { toast } from "@/components/ui/sonner";
import {
  money,
  parseNumber,
  priceIn,
  toGrams,
  unitLabel,
  unitPrice,
  weight,
} from "@/lib/format";
import type { Batch, DiscountType, Driver, Product, Unit } from "@/types";

// O Radix não aceita `value=""` num item de Select (string vazia é o estado
// "sem seleção"), então "sem entregador" precisa de um valor próprio.
const UNASSIGNED = "sem-entregador";

type Props = {
  products: Product[];
  /** Entregadores ativos, para a venda já sair com dono. */
  drivers: Driver[];
};

/**
 * Linha do carrinho. A chave é o **lote**, não o produto: dois lotes do mesmo
 * produto custaram preços diferentes e são duas linhas no pedido.
 */
type CartItem = {
  productId: string;
  batchId: string;
  name: string;
  batchLabel: string;
  grams: number;
  pricePerGram: number;
  total: number;
};

export default function NewOrder({ products, drivers }: Props) {
  const [cart, setCart] = React.useState<CartItem[]>([]);

  const { data, setData, post, processing, errors } = useForm({
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
  });

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
          <CardContent className="space-y-4 p-4">
            <Field label="Cliente" htmlFor="customer_name" hint="Opcional.">
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
                {drivers.length > 0 && (
                  <Field
                    label="Entregador"
                    htmlFor="driver_id"
                    hint="Opcional. Em branco, o pedido entra na fila e você escolhe depois."
                    error={errors.driver_id}
                  >
                    <Select
                      value={data.driver_id}
                      onValueChange={(value) =>
                        setData("driver_id", value === UNASSIGNED ? "" : value)
                      }
                    >
                      <SelectTrigger id="driver_id" aria-label="Entregador">
                        <SelectValue placeholder="Definir depois" />
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
                )}

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

/**
 * Escolher produto, dizer de qual lote sai, pesar e adicionar — o gesto que
 * mais se repete na tela.
 *
 * O lote é escolhido aqui porque é ele que carrega o custo daquela
 * mercadoria: sem essa escolha o lucro da venda seria um chute. Produto com
 * um lote só já vem escolhido, para não custar um toque a mais no balcão.
 */
const ProductPicker: React.FC<{
  products: Product[];
  onAdd: (item: CartItem) => void;
}> = ({ products, onAdd }) => {
  const [productId, setProductId] = React.useState<string>("");
  const [batchId, setBatchId] = React.useState<string>("");
  const [quantity, setQuantity] = React.useState("");
  const [unit, setUnit] = React.useState<Unit>("kg");
  const [error, setError] = React.useState<string | undefined>();

  const product = products.find((entry) => entry.id === productId);
  const batches: Batch[] = product?.batches ?? [];
  const batch = batches.find((entry) => entry.id === batchId);

  React.useEffect(() => {
    if (!product) return;

    setUnit(product.unit);
    // Um lote só: escolhe sozinho. Vários: a pessoa decide de qual tira.
    setBatchId(product.batches?.length === 1 ? product.batches[0].id : "");
  }, [product]);

  const add = () => {
    const parsed = parseNumber(quantity);

    if (!product) return setError("Escolha um produto.");
    if (!batch) return setError("Escolha o lote.");
    if (parsed === null || parsed <= 0) return setError("Informe um peso válido.");

    const grams = toGrams(parsed, unit);

    if (grams > batch.remainingGrams) {
      return setError(`Neste lote há ${weight(batch.remainingGrams)}.`);
    }

    onAdd({
      productId: product.id,
      batchId: batch.id,
      name: product.name,
      batchLabel: batch.label,
      grams,
      pricePerGram: product.pricePerGram,
      total: grams * product.pricePerGram,
    });

    setQuantity("");
    setError(undefined);
  };

  return (
    <Card>
      <CardContent className="space-y-3 p-4">
        <Field label="Produto">
          <Select value={productId} onValueChange={setProductId}>
            <SelectTrigger aria-label="Produto">
              <SelectValue placeholder="Escolher produto" />
            </SelectTrigger>
            <SelectContent>
              {products.map((entry) => (
                <SelectItem key={entry.id} value={entry.id}>
                  {entry.name} · {weight(entry.stockGrams)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>

        {product && (
          <p className="text-xs text-muted-foreground">
            {unitPrice(priceIn(product.pricePerGram, product.unit))} / {unitLabel(product.unit)} ·
            disponível {weight(product.stockGrams)}
          </p>
        )}

        {product && batches.length > 1 && (
          <Field label="Lote" hint="De qual compra está saindo.">
            <Select value={batchId} onValueChange={setBatchId}>
              <SelectTrigger aria-label="Lote">
                <SelectValue placeholder="Escolher lote" />
              </SelectTrigger>
              <SelectContent>
                {batches.map((entry) => (
                  <SelectItem key={entry.id} value={entry.id}>
                    {entry.label} · {weight(entry.remainingGrams)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
        )}

        {product && batches.length === 1 && (
          <p className="text-xs text-muted-foreground">lote {batches[0].label}</p>
        )}

        <Field label="Peso" htmlFor="quantity" error={error}>
          <div className="space-y-2">
            <Input
              id="quantity"
              inputMode="decimal"
              placeholder="0"
              value={quantity}
              onChange={(e) => setQuantity(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  add();
                }
              }}
              aria-invalid={Boolean(error)}
            />
            <UnitToggle value={unit} onChange={setUnit} />
          </div>
        </Field>

        <Button variant="secondary" className="w-full" onClick={add}>
          <Plus className="size-4" />
          Adicionar ao pedido
        </Button>
      </CardContent>
    </Card>
  );
};

/**
 * Prévia do desconto. É só para a tela — quem calcula o valor gravado é o
 * `Core.Orders.Changes.BuildOrder`.
 */
function previewDiscount(subtotal: number, type: DiscountType, rawValue: string): number {
  const value = parseNumber(rawValue) ?? 0;
  if (value <= 0) return 0;

  if (type === "percent") return Math.min((subtotal * value) / 100, subtotal);
  if (type === "amount") return Math.min(value, subtotal);
  return 0;
}
