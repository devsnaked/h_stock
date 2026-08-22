import * as React from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ComposedChart,
  Line,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Collapsible } from "@/components/ui/collapsible";
import { money } from "@/lib/format";

/**
 * Peças compartilhadas dos gráficos do painel.
 *
 * As cores vêm dos tokens (`--chart-*` em `app.css`), então o gráfico troca
 * de tema junto com o resto do app — nada de paleta escrita no JavaScript. A
 * régua é a da interface: cinza carrega a série principal e a cor só entra
 * quando quer dizer alguma coisa (verde é lucro, âmbar é estoque a resolver,
 * vermelho é venda perdida).
 */
export const SERIES = {
  neutral: "var(--chart-neutral)",
  profit: "var(--chart-profit)",
  warning: "var(--chart-warning)",
  negative: "var(--chart-negative)",
} as const;

const AXIS = {
  fontSize: 11,
  fill: "var(--muted-foreground)",
};

/** Dinheiro curto para caber no eixo do celular: R$ 1,2 mil. */
export function shortMoney(value: number): string {
  if (Math.abs(value) >= 1_000_000) return `R$ ${(value / 1_000_000).toFixed(1)} mi`;
  if (Math.abs(value) >= 1_000) return `R$ ${(value / 1_000).toFixed(1)} mil`;
  return money(value);
}

const dayLabel = (iso: string) => {
  const [, month, day] = iso.split("-");
  return `${day}/${month}`;
};

/**
 * Cartão de gráfico: título, legenda e a área do gráfico com altura fixa.
 * A legenda fica no cabeçalho porque no celular ela embaixo empurraria o
 * gráfico para fora da primeira dobra.
 */
export const ChartCard: React.FC<{
  title: string;
  hint?: string;
  legend?: { label: string; color: string }[];
  children: React.ReactNode;
}> = ({ title, hint, legend, children }) => (
  <Card>
    <CardHeader className="gap-2">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <CardTitle className="text-sm">{title}</CardTitle>

        {legend && legend.length > 1 && (
          <ul className="flex items-center gap-3">
            {legend.map((entry) => (
              <li key={entry.label} className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <span
                  aria-hidden
                  className="size-2 rounded-full"
                  style={{ backgroundColor: entry.color }}
                />
                {entry.label}
              </li>
            ))}
          </ul>
        )}
      </div>

      {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
    </CardHeader>

    <CardContent>{children}</CardContent>
  </Card>
);

/** Tooltip com a cara do app — o padrão do recharts ignora os tokens. */
const ChartTooltip: React.FC<{
  active?: boolean;
  payload?: { name?: string; value?: number; color?: string; payload?: Record<string, unknown> }[];
  label?: string | number;
  format: (value: number) => string;
  labelOf: (label: string | number) => string;
}> = ({ active, payload, label, format, labelOf }) => {
  if (!active || !payload?.length) return null;

  return (
    <div className="rounded-lg border border-border bg-card px-3 py-2 shadow-md">
      <p className="text-xs font-medium">{labelOf(label ?? "")}</p>
      <ul className="space-y-0.5 pt-1">
        {payload.map((entry) => (
          <li key={entry.name} className="flex items-center gap-2 text-xs text-muted-foreground">
            <span
              aria-hidden
              className="size-2 rounded-full"
              style={{ backgroundColor: entry.color }}
            />
            {entry.name}
            <span className="ml-auto font-medium tabular-nums text-foreground">
              {format(entry.value ?? 0)}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
};

/**
 * Faturamento por dia, com o lucro por cima.
 *
 * Duas medidas no mesmo desenho, mas **num eixo só** — lucro é parte do
 * faturamento, então dividem a mesma escala em reais e a distância entre as
 * duas linhas é justamente o custo da mercadoria.
 */
export const DailySalesChart: React.FC<{
  data: { date: string; revenue: number; profit?: number; orders: number }[];
  costs: boolean;
}> = ({ data, costs }) => (
  <ResponsiveContainer width="100%" height={220}>
    <ComposedChart data={data} margin={{ top: 8, right: 4, bottom: 0, left: -12 }}>
      <CartesianGrid vertical={false} stroke="var(--border)" />
      <XAxis
        dataKey="date"
        tickFormatter={dayLabel}
        tick={AXIS}
        axisLine={false}
        tickLine={false}
        minTickGap={16}
      />
      <YAxis tickFormatter={shortMoney} tick={AXIS} axisLine={false} tickLine={false} width={64} />
      <Tooltip
        cursor={{ fill: "var(--accent)" }}
        content={
          <ChartTooltip format={money} labelOf={(label) => dayLabel(String(label))} />
        }
      />
      <Bar name="Faturamento" dataKey="revenue" fill={SERIES.neutral} radius={[4, 4, 0, 0]} />
      {costs && (
        <Line
          name="Lucro"
          type="monotone"
          dataKey="profit"
          stroke={SERIES.profit}
          strokeWidth={2}
          dot={false}
        />
      )}
    </ComposedChart>
  </ResponsiveContainer>
);

/** Pedidos por hora do dia: a que horas a loja realmente vende. */
export const HourlyChart: React.FC<{
  data: { hour: number; orders: number; revenue: number }[];
}> = ({ data }) => (
  <ResponsiveContainer width="100%" height={180}>
    <BarChart data={data} margin={{ top: 8, right: 4, bottom: 0, left: -20 }}>
      <CartesianGrid vertical={false} stroke="var(--border)" />
      <XAxis
        dataKey="hour"
        tickFormatter={(hour: number) => `${hour}h`}
        tick={AXIS}
        axisLine={false}
        tickLine={false}
        interval={2}
      />
      <YAxis allowDecimals={false} tick={AXIS} axisLine={false} tickLine={false} width={32} />
      <Tooltip
        cursor={{ fill: "var(--accent)" }}
        content={
          <ChartTooltip
            format={(value) => String(value)}
            labelOf={(label) => `${label}h às ${Number(label) + 1}h`}
          />
        }
      />
      <Bar name="Pedidos" dataKey="orders" fill={SERIES.neutral} radius={[4, 4, 0, 0]} />
    </BarChart>
  </ResponsiveContainer>
);

/**
 * Ranking horizontal. Barra deitada porque os rótulos são nomes — de produto,
 * de pessoa, de entregador — e nome não cabe em pé no celular.
 */
export const RankingChart: React.FC<{
  data: { name: string; value: number }[];
  color?: string;
  format?: (value: number) => string;
  unit: string;
}> = ({ data, color = SERIES.neutral, format = money, unit }) => (
  <ResponsiveContainer width="100%" height={Math.max(120, data.length * 34)}>
    <BarChart data={data} layout="vertical" margin={{ top: 0, right: 12, bottom: 0, left: 0 }}>
      <XAxis type="number" hide />
      <YAxis
        type="category"
        dataKey="name"
        tick={AXIS}
        axisLine={false}
        tickLine={false}
        width={110}
      />
      <Tooltip
        cursor={{ fill: "var(--accent)" }}
        content={<ChartTooltip format={format} labelOf={(label) => String(label)} />}
      />
      <Bar name={unit} dataKey="value" fill={color} radius={[0, 4, 4, 0]} barSize={18} />
    </BarChart>
  </ResponsiveContainer>
);

/**
 * Tabela do gráfico. Não é enfeite: é como quem não distingue as cores (ou
 * abriu num aparelho minúsculo) lê os mesmos números.
 */
export const ChartTable: React.FC<{
  columns: string[];
  rows: (string | number)[][];
}> = ({ columns, rows }) => (
  <Collapsible label="Ver os números" className="pt-2">
    <div className="overflow-x-auto">
      <table className="w-full text-xs">
        <thead>
          <tr className="text-muted-foreground">
            {columns.map((column, index) => (
              <th key={column} className={index === 0 ? "py-1 text-left" : "py-1 text-right"}>
                {column}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={String(row[0])} className="border-t border-border">
              {row.map((cell, index) => (
                <td
                  key={index}
                  className={index === 0 ? "py-1 text-left" : "py-1 text-right tabular-nums"}
                >
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  </Collapsible>
);
