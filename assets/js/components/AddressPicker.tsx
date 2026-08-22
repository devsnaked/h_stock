import * as React from "react";
import { MapPin, Search, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Field } from "@/components/ui/label";
import { AddressMap } from "@/components/AddressMap";
import type { Place } from "@/types";

type Props = {
  address: string;
  lat: number | null;
  lon: number | null;
  onChange: (value: { address: string; lat: number | null; lon: number | null }) => void;
};

/**
 * Endereço de entrega com mapa.
 *
 * A busca é **por gesto**, não a cada tecla: o Nominatim pede no máximo uma
 * consulta por segundo, e quem digita endereço no balcão termina a frase
 * antes de esperar resposta. Enter no campo também busca.
 *
 * Achar o ponto é opcional de propósito. O endereço escrito já basta para
 * entregar — o mapa é o que evita a ligação de "é na rua de cima ou na de
 * baixo?". Serviço fora do ar não pode impedir o registro da venda.
 */
export const AddressPicker: React.FC<Props> = ({ address, lat, lon, onChange }) => {
  const [results, setResults] = React.useState<Place[] | null>(null);
  const [searching, setSearching] = React.useState(false);
  const [failed, setFailed] = React.useState(false);

  const located = lat !== null && lon !== null;

  const search = async () => {
    const query = address.trim();
    if (query === "") return;

    setSearching(true);
    setFailed(false);

    try {
      // Sem `Accept: application/json`: o pipeline do browser aceita "html",
      // e o que importa é o corpo, que o controller manda como JSON.
      const response = await fetch(`/pedidos/endereco?q=${encodeURIComponent(query)}`, {
        credentials: "same-origin",
      });

      const body = (await response.json()) as { available: boolean; results: Place[] };

      setResults(body.results);
      setFailed(!body.available);
    } catch {
      setResults([]);
      setFailed(true);
    } finally {
      setSearching(false);
    }
  };

  const choose = (place: Place) => {
    onChange({ address: place.label, lat: place.lat, lon: place.lon });
    setResults(null);
  };

  return (
    <div className="space-y-3">
      <Field
        label="Endereço da entrega"
        htmlFor="delivery_address"
        hint="Rua, número e bairro. Busque para conferir no mapa."
      >
        <div className="flex gap-2">
          <Input
            id="delivery_address"
            autoComplete="off"
            placeholder="Rua das Flores, 100 — Centro"
            value={address}
            onChange={(event) => {
              // Mexeu no texto? O ponto que estava no mapa era de outro
              // endereço; some até a próxima busca.
              onChange({ address: event.target.value, lat: null, lon: null });
              setResults(null);
            }}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                void search();
              }
            }}
          />

          <Button
            variant="outline"
            size="icon"
            aria-label="Procurar no mapa"
            disabled={searching || address.trim() === ""}
            onClick={() => void search()}
          >
            <Search className="size-4" />
          </Button>
        </div>
      </Field>

      {searching && <p className="text-xs text-muted-foreground">Procurando o endereço...</p>}

      {failed && (
        <p className="text-xs text-muted-foreground">
          Não deu para consultar o mapa agora. O pedido pode ser registrado só
          com o endereço escrito.
        </p>
      )}

      {results !== null && results.length === 0 && !failed && (
        <p className="text-xs text-muted-foreground">
          Nenhum endereço encontrado. Tente com o nome da cidade no fim.
        </p>
      )}

      {results !== null && results.length > 0 && (
        <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border">
          {results.map((place) => (
            <li key={`${place.lat},${place.lon}`}>
              <button
                type="button"
                onClick={() => choose(place)}
                className="flex w-full items-start gap-2 p-3 text-left text-sm hover:bg-accent"
              >
                <MapPin className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
                <span className="min-w-0 flex-1">{place.label}</span>
              </button>
            </li>
          ))}
        </ul>
      )}

      {located && (
        <div className="space-y-2">
          <AddressMap lat={lat} lon={lon} label={address} />

          <button
            type="button"
            onClick={() => onChange({ address, lat: null, lon: null })}
            className="flex items-center gap-1 text-xs text-muted-foreground underline underline-offset-4"
          >
            <X className="size-3" />
            Tirar o ponto do mapa
          </button>
        </div>
      )}
    </div>
  );
};
