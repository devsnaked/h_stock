import * as React from "react";
import { Badge } from "@/components/ui/badge";
import type { Order } from "@/types";

/**
 * Situação da venda a prazo: a receber, vencida ou paga.
 *
 * Venda à vista não mostra nada — foi paga no balcão, e um "pago" em todo
 * pedido da lista seria ruído. Cancelado também não: não deve nada.
 * "Vencido" vem pronto do servidor, que sabe que dia é hoje na loja.
 */
export const PaymentBadge: React.FC<{ order: Order }> = ({ order }) => {
  if (order.status === "cancelled" || order.paymentDueOn === null) return null;
  if (order.paidAt !== null) return <Badge variant="secondary">pago</Badge>;
  if (order.paymentOverdue) return <Badge variant="warning">vencido</Badge>;

  return <Badge variant="outline">a receber</Badge>;
};
