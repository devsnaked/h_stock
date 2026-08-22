import * as React from "react";
import { useForm } from "@inertiajs/react";
import { AppLayout } from "@/layouts/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { MoneyInput } from "@/components/ui/money-input";
import { Field } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { UnitToggle } from "@/components/UnitToggle";
import { moneyInput, priceIn, remaskMoney, unitLabel } from "@/lib/format";
import { fieldErrors } from "@/lib/errors";
import type { Product, Unit } from "@/types";

type Props = { product: Product | null };

type Form = {
  name: string;
  unit: Unit;
  /** Preço na unidade escolhida; o servidor converte para preço por grama. */
  price: string;
  min_stock: string;
  initial_stock: string;
  /** Custo do estoque inicial, na unidade escolhida. */
  initial_cost: string;
  initial_batch_label: string;
  active: boolean;
};

/**
 * Casas da máscara de dinheiro. Por kg são centavos; por grama o preço mora
 * na terceira e quarta casa (R$ 0,0620/g = R$ 62,00/kg), e arredondar ali
 * mudaria o preço do produto.
 */
const moneyDecimals = (unit: Unit) => (unit === "kg" ? 2 : 4);

export default function ProductForm({ product }: Props) {
  const editing = product !== null;

  const form = useForm<Form>({
    name: product?.name ?? "",
    unit: product?.unit ?? "kg",
    price: product
      ? moneyInput(priceIn(product.pricePerGram, product.unit), moneyDecimals(product.unit))
      : "",
    min_stock: product
      ? String(product.unit === "kg" ? product.minStockGrams / 1000 : product.minStockGrams)
      : "",
    initial_stock: "",
    initial_cost: "",
    initial_batch_label: "",
    active: product?.active ?? true,
  });

  const { data, setData, post, put, processing } = form;
  const errors = fieldErrors(form.errors);
  const decimals = moneyDecimals(data.unit);

  // Trocar a unidade não muda o número digitado, só quantas casas ele mostra:
  // 62,00 por kg passa a 62,0000 por grama, e quem digitou decide o resto.
  const chooseUnit = (unit: Unit) => {
    const next = moneyDecimals(unit);

    setData((current) => ({
      ...current,
      unit,
      price: remaskMoney(current.price, next),
      initial_cost: remaskMoney(current.initial_cost, next),
    }));
  };

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    if (editing) {
      put(`/produtos/${product.id}`);
    } else {
      post("/produtos");
    }
  };

  return (
    <AppLayout
      title={editing ? "Editar produto" : "Novo produto"}
      back={editing ? `/produtos/${product.id}` : "/produtos"}
    >
      <form className="space-y-4" onSubmit={submit}>
        <Card>
          <CardContent className="space-y-4 p-4">
            <Field label="Nome" htmlFor="name" error={errors.name}>
              <Input
                id="name"
                required
                autoFocus={!editing}
                value={data.name}
                onChange={(e) => setData("name", e.target.value)}
                aria-invalid={Boolean(errors.name)}
              />
            </Field>

            <Field
              label="Unidade de venda"
              hint="Como o produto é pesado no balcão. O preço é guardado sempre por grama."
            >
              <UnitToggle value={data.unit} onChange={chooseUnit} />
            </Field>

            <Field
              label={`Preço por ${unitLabel(data.unit)}`}
              htmlFor="price"
              error={errors.price_per_gram ?? errors.price}
              hint={
                data.unit === "kg"
                  ? "Ex.: 62,00 por kg equivale a R$ 0,062 por grama."
                  : "Ex.: 0,85 por grama."
              }
            >
              <MoneyInput
                id="price"
                required
                decimals={decimals}
                value={data.price}
                onChange={(value) => setData("price", value)}
                aria-invalid={Boolean(errors.price_per_gram ?? errors.price)}
              />
            </Field>

            <Field
              label={`Estoque mínimo (${unitLabel(data.unit)})`}
              htmlFor="min_stock"
              error={errors.min_stock_grams}
              hint="Abaixo disso o produto aparece como estoque baixo."
            >
              <Input
                id="min_stock"
                inputMode="decimal"
                placeholder="0"
                value={data.min_stock}
                onChange={(e) => setData("min_stock", e.target.value)}
              />
            </Field>

            {!editing && (
              <>
                <Field
                  label={`Estoque inicial (${unitLabel(data.unit)})`}
                  htmlFor="initial_stock"
                  error={errors.initial_stock_grams}
                  hint="Vira o primeiro lote do produto."
                >
                  <Input
                    id="initial_stock"
                    inputMode="decimal"
                    placeholder="0"
                    value={data.initial_stock}
                    onChange={(e) => setData("initial_stock", e.target.value)}
                  />
                </Field>

                {/* Sem custo não há lucro: o campo aparece junto do estoque
                    inicial, e não numa tela separada depois. */}
                <Field
                  label={`Custo do estoque inicial (por ${unitLabel(data.unit)})`}
                  htmlFor="initial_cost"
                  error={errors.initial_cost_per_gram ?? errors.initial_cost}
                  hint="Quanto essa mercadoria custou. Sem isso o lucro dela sai cheio."
                >
                  <MoneyInput
                    id="initial_cost"
                    decimals={decimals}
                    value={data.initial_cost}
                    onChange={(value) => setData("initial_cost", value)}
                  />
                </Field>

                <Field
                  label="Nome do primeiro lote"
                  htmlFor="initial_batch_label"
                  hint="Opcional. Em branco vira a data de hoje."
                >
                  <Input
                    id="initial_batch_label"
                    placeholder="Compra de estreia"
                    value={data.initial_batch_label}
                    onChange={(e) => setData("initial_batch_label", e.target.value)}
                  />
                </Field>
              </>
            )}

            <label className="flex items-center justify-between gap-3 pt-1">
              <span className="space-y-0.5">
                <span className="block text-sm font-medium">À venda</span>
                <span className="block text-xs text-muted-foreground">
                  Produtos inativos não aparecem em novos pedidos.
                </span>
              </span>
              <Switch
                checked={data.active}
                onCheckedChange={(checked) => setData("active", checked)}
              />
            </label>
          </CardContent>
        </Card>

        {errors.form && (
          <p className="text-sm font-medium text-destructive">{errors.form}</p>
        )}

        <Button type="submit" size="lg" className="w-full" disabled={processing}>
          {processing ? "Salvando..." : editing ? "Salvar alterações" : "Cadastrar produto"}
        </Button>
      </form>
    </AppLayout>
  );
}
