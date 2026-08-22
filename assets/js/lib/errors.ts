/**
 * Erros de validação vindos do servidor.
 *
 * O `useForm` do Inertia tipa `errors` com as chaves do formulário, mas o
 * backend fala a língua do domínio: um erro no preço volta como
 * `price_per_gram`, e problemas sem campo definido voltam como `form`. Este
 * alias dá acesso a qualquer chave sem espalhar `as any` pelas páginas.
 */
export type FieldErrors = Record<string, string | undefined>;

export const fieldErrors = (errors: unknown): FieldErrors =>
  (errors ?? {}) as FieldErrors;
