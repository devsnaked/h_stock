import type { Unit } from "@/types";

const brl = new Intl.NumberFormat("pt-BR", {
  style: "currency",
  currency: "BRL",
});

// Preço por grama costuma ter mais de duas casas (R$ 0,062/g). Arredondar
// para centavos aqui esconderia a diferença entre 0,062 e 0,068.
const brlPrecise = new Intl.NumberFormat("pt-BR", {
  style: "currency",
  currency: "BRL",
  minimumFractionDigits: 2,
  maximumFractionDigits: 4,
});

const dateTime = new Intl.DateTimeFormat("pt-BR", {
  day: "2-digit",
  month: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
});

export const money = (value: number) => brl.format(value ?? 0);

/** Valores por grama, onde os centavos não bastam. */
export const unitPrice = (value: number) => brlPrecise.format(value ?? 0);

/**
 * Peso legível. Abaixo de 1kg mostra em gramas — é como se fala no balcão
 * ("500g"), não "0,5kg".
 */
export function weight(grams: number): string {
  const value = grams ?? 0;

  if (Math.abs(value) >= 1000) {
    return `${trim(value / 1000)} kg`;
  }

  return `${trim(value)} g`;
}

/** Converte para gramas o que foi digitado numa unidade. */
export const toGrams = (quantity: number, unit: Unit) =>
  unit === "kg" ? quantity * 1000 : quantity;

/** Aceita vírgula decimal — é o que o teclado do celular oferece em pt-BR. */
export function parseNumber(value: string): number | null {
  const normalized = value.trim().replace(",", ".");
  if (normalized === "") return null;

  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * Máscara monetária: os dígitos entram pela direita, como numa maquininha —
 * digitar "6200" vira "62,00". É o único jeito que não obriga a pessoa a
 * caçar a vírgula no teclado do celular.
 *
 * O que sai é o valor **canônico do formulário**: vírgula decimal e nenhum
 * separador de milhar, que é o formato que `Web.ControllerHelpers.to_decimal/1`
 * entende ("1.234,56" viraria erro de número).
 */
export function maskMoney(input: string, decimals = 2): string {
  // 12 dígitos: R$ 9.999.999.999,99 é folgado para qualquer venda desta loja
  // e evita que segurar uma tecla vire um número absurdo.
  const digits = input.replace(/\D/g, "").slice(0, 12);
  if (digits === "") return "";
  if (decimals <= 0) return String(Number(digits));

  const padded = digits.padStart(decimals + 1, "0");
  const whole = padded.slice(0, -decimals).replace(/^0+(?=\d)/, "");

  return `${whole},${padded.slice(-decimals)}`;
}

/** Valor canônico como a pessoa lê, com separador de milhar. */
export function moneyDisplay(value: string, decimals = 2): string {
  const parsed = parseNumber(value);
  if (value === "" || parsed === null) return value;

  return parsed.toLocaleString("pt-BR", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

/** Número para o valor canônico da máscara (`62` -> `"62,00"`). */
export function moneyInput(value: number | null | undefined, decimals = 2): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "";
  return value.toFixed(decimals).replace(".", ",");
}

/**
 * Reaplica a máscara com outro número de casas. Serve à troca de unidade:
 * preço por kg tem centavos, por grama precisa de quatro casas (R$ 0,0620).
 */
export const remaskMoney = (value: string, decimals: number) =>
  moneyInput(parseNumber(value), decimals);

/** Preço por grama exibido na unidade do produto. */
export const priceIn = (pricePerGram: number, unit: Unit) =>
  unit === "kg" ? pricePerGram * 1000 : pricePerGram;

export const unitLabel = (unit: Unit) => (unit === "kg" ? "kg" : "g");

export const dateTimeLabel = (iso: string) => dateTime.format(new Date(iso));

/** Tira zeros à direita: 1,50 -> 1,5 e 2,00 -> 2. */
function trim(value: number): string {
  return value
    .toFixed(3)
    .replace(/\.?0+$/, "")
    .replace(".", ",");
}
