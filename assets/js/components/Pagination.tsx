import * as React from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";

/** Recorte devolvido pelo servidor — ver a paginação dos recursos Ash. */
export type Page = {
  number: number;
  size: number;
  count: number;
  pages: number;
};

/**
 * Paginação de lista.
 *
 * Anterior/próxima em vez de números: no celular a lista é rolada com o
 * polegar, e o que se quer é continuar de onde parou — não pular para a
 * página 7. A contagem ("21–40 de 175") fica à esquerda porque é ela que diz
 * se vale continuar rolando.
 *
 * Uma página só: o contador continua, os botões somem — não há para onde ir.
 */
export const Pagination: React.FC<{
  page: Page;
  /** Nome do que está sendo contado, no singular. */
  label: string;
  onPage: (number: number) => void;
}> = ({ page, label, onPage }) => {
  if (page.count === 0) return null;

  const first = (page.number - 1) * page.size + 1;
  const last = Math.min(page.number * page.size, page.count);

  return (
    <div className="flex items-center justify-between gap-3 pt-1">
      <p className="text-xs text-muted-foreground">
        {first}–{last} de {page.count} {page.count === 1 ? label : `${label}s`}
      </p>

      {page.pages > 1 && (
        <div className="flex items-center gap-1">
          <Button
            variant="outline"
            size="sm"
            aria-label="Página anterior"
            disabled={page.number <= 1}
            onClick={() => onPage(page.number - 1)}
          >
            <ChevronLeft className="size-4" />
            Anterior
          </Button>

          <span className="px-1 text-xs tabular-nums text-muted-foreground">
            {page.number}/{page.pages}
          </span>

          <Button
            variant="outline"
            size="sm"
            aria-label="Próxima página"
            disabled={page.number >= page.pages}
            onClick={() => onPage(page.number + 1)}
          >
            Próxima
            <ChevronRight className="size-4" />
          </Button>
        </div>
      )}
    </div>
  );
};
