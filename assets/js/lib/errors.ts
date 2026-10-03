/**
 * Erros de validação vindos do servidor.
 *
 * O `useForm` do Inertia tipa `errors` com as chaves do formulário, mas o
 * backend fala a língua do domínio: um erro no preço volta como
 * `price_per_gram`, e problemas sem campo definido voltam como `form`. Este
 * alias dá acesso a qualquer chave sem espalhar `as any` pelas páginas.
 */
export type FieldErrors = Record<string, string | undefined>;

/**
 * As chaves voltam ao snake_case do domínio. O `camelize_props` do servidor
 * cameliza os erros junto com os outros props (`customer_name` chega como
 * `customerName`), e o formulário procura pelo nome do campo — sem isto, todo
 * erro de campo com duas palavras sumia da tela e sobrava só o toast.
 */
export const fieldErrors = (errors: unknown): FieldErrors =>
  Object.fromEntries(
    Object.entries((errors ?? {}) as FieldErrors).map(([key, message]) => [
      key.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`),
      message,
    ]),
  );
