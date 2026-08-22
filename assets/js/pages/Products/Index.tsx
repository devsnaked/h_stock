import * as React from "react";
import { Link, router } from "@inertiajs/react";
import { Package, Plus, Search } from "lucide-react";
import { AppLayout } from "@/layouts/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { useAuth } from "@/hooks/useAuth";
import { priceIn, unitLabel, unitPrice, weight } from "@/lib/format";
import type { Product } from "@/types";

type Props = { products: Product[]; search: string | null };

export default function ProductsIndex({ products, search }: Props) {
  const { managesStock } = useAuth();
  const [term, setTerm] = React.useState(search ?? "");

  // Busca no servidor com debounce: no celular, cada tecla disparando uma
  // requisição atrapalha mais do que ajuda.
  React.useEffect(() => {
    if (term === (search ?? "")) return;

    const timer = setTimeout(() => {
      router.get(
        "/produtos",
        term ? { q: term } : {},
        { preserveState: true, replace: true },
      );
    }, 300);

    return () => clearTimeout(timer);
  }, [term, search]);

  return (
    <AppLayout
      title="Estoque"
      subtitle={`${products.length} ${products.length === 1 ? "produto" : "produtos"}`}
      action={
        managesStock ? (
          <Button asChild size="sm">
            <Link href="/produtos/novo">
              <Plus className="size-4" />
              Novo
            </Link>
          </Button>
        ) : undefined
      }
    >
      <div className="space-y-4">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={term}
            onChange={(e) => setTerm(e.target.value)}
            placeholder="Buscar produto"
            className="pl-9"
            type="search"
            aria-label="Buscar produto"
          />
        </div>

        {products.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
              <Package className="size-8 text-muted-foreground/60" />
              <p className="text-sm text-muted-foreground">
                {term ? "Nenhum produto encontrado." : "Nenhum produto cadastrado."}
              </p>
              {managesStock && !term && (
                <Button asChild variant="outline" size="sm">
                  <Link href="/produtos/novo">Cadastrar o primeiro</Link>
                </Button>
              )}
            </CardContent>
          </Card>
        ) : (
          <ul className="space-y-2">
            {products.map((product) => (
              <li key={product.id}>
                <Link href={`/produtos/${product.id}`}>
                  <Card className="transition-colors active:bg-accent">
                    <CardContent className="flex items-center justify-between gap-3 p-4">
                      <div className="min-w-0 space-y-1">
                        <p className="truncate font-medium">{product.name}</p>
                        <p className="text-xs text-muted-foreground">
                          {unitPrice(priceIn(product.pricePerGram, product.unit))} /{" "}
                          {unitLabel(product.unit)}
                        </p>
                      </div>

                      <div className="flex shrink-0 flex-col items-end gap-1">
                        <span className="text-sm font-semibold tabular-nums">
                          {weight(product.stockGrams)}
                        </span>
                        {!product.active ? (
                          <Badge variant="outline">inativo</Badge>
                        ) : product.lowStock ? (
                          <Badge variant="warning">estoque baixo</Badge>
                        ) : null}
                      </div>
                    </CardContent>
                  </Card>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </div>
    </AppLayout>
  );
}
