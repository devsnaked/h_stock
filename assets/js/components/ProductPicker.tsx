import * as React from "react";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { UnitToggle } from "@/components/UnitToggle";
import { parseNumber, priceIn, toGrams, unitLabel, unitPrice, weight } from "@/lib/format";
import type { Batch, DiscountType, Product, Unit } from "@/types";

/**
 * Linha do carrinho. A chave é o **lote**, não o produto: dois lotes do mesmo
 * produto custaram preços diferentes e são duas linhas no pedido.
 */
export type CartItem = {
  productId: string;
  batchId: string;
  name: string;
  batchLabel: string;
  grams: number;
  pricePerGram: number;
  total: number;
};

/**
 * Escolher produto, dizer de qual lote sai, pesar e adicionar — o gesto que
 * mais se repete na tela.
 *
 * O lote é escolhido aqui porque é ele que carrega o custo daquela
 * mercadoria: sem essa escolha o lucro da venda seria um chute. Produto com
 * um lote só já vem escolhido, para não custar um toque a mais no balcão.
 */
export const ProductPicker: React.FC<{
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
 * `Core.Orders.Changes.BuildOrder` (e, na edição, o `EditItems`).
 */
export function previewDiscount(subtotal: number, type: DiscountType, rawValue: string): number {
  const value = parseNumber(rawValue) ?? 0;
  if (value <= 0) return 0;

  if (type === "percent") return Math.min((subtotal * value) / 100, subtotal);
  if (type === "amount") return Math.min(value, subtotal);
  return 0;
}
