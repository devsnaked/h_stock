import * as React from "react";
import L from "leaflet";
import { cn } from "@/lib/utils";

type Props = {
  lat: number;
  lon: number;
  /** Texto do balão do ponto — normalmente o endereço escolhido. */
  label?: string | null;
  className?: string;
};

/**
 * Mapa do endereço de entrega.
 *
 * Leaflet com tiles do OpenStreetMap: nenhuma chave de API para gerenciar e
 * nenhum script de terceiro na página — a biblioteca entra no bundle como
 * qualquer outra dependência.
 *
 * O ponto é um `circleMarker` (SVG) em vez do pino padrão de propósito: o
 * pino do Leaflet é um PNG que ele monta por caminho relativo, e num bundle
 * com hash no nome esse caminho não existe. Um círculo não depende de imagem
 * nenhuma e ainda usa a cor do tema.
 *
 * O zoom pela roda do mouse fica desligado: o mapa mora no meio de um
 * formulário, e rolar a página não pode virar zoom sem querer.
 */
export const AddressMap: React.FC<Props> = ({ lat, lon, label, className }) => {
  const container = React.useRef<HTMLDivElement | null>(null);
  const map = React.useRef<L.Map | null>(null);
  const marker = React.useRef<L.CircleMarker | null>(null);

  React.useEffect(() => {
    if (!container.current || map.current) return;

    const instance = L.map(container.current, {
      center: [lat, lon],
      zoom: 16,
      scrollWheelZoom: false,
      zoomControl: true,
    });

    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: "© OpenStreetMap",
    }).addTo(instance);

    marker.current = L.circleMarker([lat, lon], {
      radius: 9,
      weight: 3,
      color: "#ef4444",
      fillColor: "#ef4444",
      fillOpacity: 0.35,
    }).addTo(instance);

    map.current = instance;

    return () => {
      instance.remove();
      map.current = null;
      marker.current = null;
    };
    // Só na montagem: mudanças de coordenada são tratadas no efeito abaixo,
    // que move o mapa em vez de recriá-lo.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  React.useEffect(() => {
    map.current?.setView([lat, lon], map.current.getZoom() ?? 16);
    marker.current?.setLatLng([lat, lon]);
  }, [lat, lon]);

  React.useEffect(() => {
    if (!marker.current) return;

    if (label) marker.current.bindTooltip(label, { direction: "top" });
    else marker.current.unbindTooltip();
  }, [label]);

  return (
    <div
      ref={container}
      role="img"
      aria-label={label ? `Mapa de ${label}` : "Mapa do endereço"}
      className={cn("h-52 w-full overflow-hidden rounded-xl border border-border", className)}
    />
  );
};
