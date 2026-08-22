import * as React from "react";
import { Badge } from "@/components/ui/badge";
import type { DeliveryStatus, Order } from "@/types";

const LABEL: Record<DeliveryStatus, string> = {
  not_required: "retirada",
  pending: "a entregar",
  out_for_delivery: "a caminho",
  delivered: "entregue",
};

const VARIANT: Record<
  DeliveryStatus,
  React.ComponentProps<typeof Badge>["variant"]
> = {
  not_required: "outline",
  pending: "warning",
  out_for_delivery: "default",
  delivered: "secondary",
};

export const deliveryLabel = (status: DeliveryStatus) => LABEL[status];

/**
 * Situação da entrega. Pedido cancelado não mostra nada: a entrega deixou de
 * fazer sentido, e um "a entregar" ao lado de "cancelado" só confundiria.
 */
export const DeliveryBadge: React.FC<{ order: Order }> = ({ order }) => {
  if (order.status === "cancelled") return null;
  if (order.deliveryStatus === "not_required") return null;

  return <Badge variant={VARIANT[order.deliveryStatus]}>{LABEL[order.deliveryStatus]}</Badge>;
};
