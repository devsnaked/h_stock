import * as React from "react";
import { Link, useForm } from "@inertiajs/react";
import { Bike, CalendarClock, MapPin, Navigation, Pencil } from "lucide-react";
import { AppLayout } from "@/layouts/AppLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/input";
import { Field } from "@/components/ui/label";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { DeliveryBadge } from "@/components/DeliveryBadge";
import { PaymentBadge } from "@/components/PaymentBadge";
import { AddressMap } from "@/components/AddressMap";
import { useAuth } from "@/hooks/useAuth";
import { dateLabel, dateTimeLabel, money, unitPrice, weight } from "@/lib/format";
import type { Driver, Order } from "@/types";

type Props = { order: Order; drivers: Driver[] };

export default function OrderShow({ order, drivers }: Props) {
  const cancelled = order.status === "cancelled";
  const { isDriver } = useAuth();

  return (
    <AppLayout
      title={`Pedido ${order.code}`}
      subtitle={dateTimeLabel(order.insertedAt)}
      back="/pedidos"
    >
      <div className="space-y-4">
        {cancelled && (
          <div className="rounded-xl border border-destructive/30 bg-destructive/10 p-4">
            <p className="text-sm font-medium text-destructive">Pedido cancelado</p>
            <p className="text-xs text-destructive/80">
              Os itens voltaram para o estoque
              {order.cancelledAt ? ` em ${dateTimeLabel(order.cancelledAt)}` : ""}.
            </p>
          </div>
        )}

        {!cancelled && order.deliveryStatus !== "not_required" && (
          <Delivery order={order} drivers={drivers} />
        )}

        {/* Venda a prazo: quando vence e se já entrou. Fica logo abaixo da
            entrega porque, num pedido a prazo, dar baixa é a outra coisa que
            se vem fazer nesta tela. */}
        {order.paymentDueOn !== null && <Payment order={order} />}

        <Card>
          <CardHeader>
            <CardTitle className="text-sm">Itens</CardTitle>
          </CardHeader>
          <CardContent>
            <ul className="divide-y divide-border">
              {(order.items ?? []).map((item) => (
                <li key={item.id} className="flex items-center justify-between gap-3 py-3">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{item.productName}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      {weight(item.grams)} × {unitPrice(item.pricePerGram)}/g
                      {item.batchLabel ? ` · ${item.batchLabel}` : ""}
                    </p>
                    {item.totalCost !== undefined && (
                      <p className="text-xs text-muted-foreground">
                        custo {money(item.totalCost)}
                      </p>
                    )}
                  </div>
                  <span className="shrink-0 text-sm font-semibold tabular-nums">
                    {money(item.total)}
                  </span>
                </li>
              ))}
            </ul>

            <dl className="space-y-1 border-t border-border pt-3 text-sm">
              <div className="flex justify-between text-muted-foreground">
                <dt>Subtotal</dt>
                <dd className="tabular-nums">{money(order.subtotal)}</dd>
              </div>
              {order.discountTotal > 0 && (
                <div className="flex justify-between text-muted-foreground">
                  <dt>
                    Desconto
                    {order.discountType === "percent" && ` (${order.discountValue}%)`}
                  </dt>
                  <dd className="tabular-nums">- {money(order.discountTotal)}</dd>
                </div>
              )}
              <div className="flex justify-between border-t border-border pt-1 text-base font-semibold">
                <dt>Total</dt>
                <dd className="tabular-nums">{money(order.total)}</dd>
              </div>

              {/* Custo e lucro só chegam para quem gerencia estoque — o
                  backend simplesmente não manda os campos para os outros. */}
              {order.profit !== undefined && (
                <>
                  <div className="flex justify-between pt-1 text-muted-foreground">
                    <dt>Custo da mercadoria</dt>
                    <dd className="tabular-nums">{money(order.costTotal ?? 0)}</dd>
                  </div>
                  <div className="flex justify-between font-medium">
                    <dt>Lucro</dt>
                    <dd className="tabular-nums">{money(order.profit)}</dd>
                  </div>
                </>
              )}
            </dl>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="space-y-2 p-4 text-sm">
            <Row label="Cliente" value={order.customerName ?? "não informado"} />
            <Row label="Registrado por" value={order.userName ?? "—"} />
            {order.paymentDueOn === null && <Row label="Pagamento" value="à vista" />}
            {order.deliveryStatus === "not_required" && (
              <Row label="Entrega" value="retirada no balcão" />
            )}
            {order.note && <Row label="Observação" value={order.note} />}
            <Row
              label="Situação"
              value={
                cancelled ? (
                  <Badge variant="destructive">cancelado</Badge>
                ) : (
                  <Badge>concluído</Badge>
                )
              }
            />

            {/* Só o admin recebe estes campos — para os outros o servidor nem
                os manda. O que havia antes de cada edição está no log. */}
            {order.editedAt && (
              <div className="border-t border-border pt-2">
                <Row
                  label="Editado"
                  value={`${order.editedByName ?? "—"} · ${dateTimeLabel(order.editedAt)}`}
                />
                <Link
                  href={`/auditoria?tipo=pedidos&busca=${order.code}`}
                  className="mt-1 block text-right text-xs font-medium underline underline-offset-4"
                >
                  ver o que mudou
                </Link>
              </div>
            )}
          </CardContent>
        </Card>

        {/* O entregador abre esta tela para saber para onde ir; editar e
            cancelar venda são do balcão. */}
        {!cancelled && !isDriver && (
          <div className="grid gap-2">
            <Button asChild variant="outline" className="w-full">
              <Link href={`/pedidos/${order.id}/editar`}>
                <Pencil className="size-4" />
                Editar pedido
              </Link>
            </Button>
            <CancelDialog order={order} />
          </div>
        )}
      </div>
    </AppLayout>
  );
}

/**
 * Venda a prazo: o dia combinado, a baixa e o botão de dar baixa.
 *
 * Baixa é do balcão — o entregador abre esta tela para entregar, não para
 * receber. Pedido cancelado mostra o vencimento só como histórico: não deve
 * nada, então não há o que receber.
 */
const Payment: React.FC<{ order: Order }> = ({ order }) => {
  const { isDriver } = useAuth();
  const open = order.status === "completed" && order.paidAt === null;

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between">
        <CardTitle className="flex items-center gap-2 text-sm">
          <CalendarClock className="size-4 text-muted-foreground" />
          Pagamento a prazo
        </CardTitle>
        <PaymentBadge order={order} />
      </CardHeader>

      <CardContent className="space-y-3 text-sm">
        <Row label="Vence em" value={dateLabel(order.paymentDueOn ?? "")} />
        {order.paidAt !== null && <Row label="Pago em" value={dateTimeLabel(order.paidAt)} />}

        {order.paymentOverdue && (
          <p className="rounded-lg border border-warning/30 bg-warning/10 p-3 text-xs text-warning-foreground">
            O dia combinado já passou e o pagamento ainda não foi registrado.
          </p>
        )}

        {open && !isDriver && <MarkPaidDialog order={order} />}
      </CardContent>
    </Card>
  );
};

/**
 * Dar baixa pede confirmação — não há desfazer na tela, e um toque errado
 * deixaria de cobrar quem ainda deve. É uma folha (`Dialog`), e não o
 * `AlertDialog`, porque receber não é destrutivo: o botão é o principal, não
 * o vermelho.
 */
const MarkPaidDialog: React.FC<{ order: Order }> = ({ order }) => {
  const [open, setOpen] = React.useState(false);
  const { post, processing } = useForm({});

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="lg" className="w-full">
          Marcar como pago
        </Button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <DialogTitle>O pedido {order.code} foi pago?</DialogTitle>
          <DialogDescription>
            {money(order.total)}
            {order.customerName ? ` de ${order.customerName}` : ""}. O pedido sai da lista
            de não pagos, e a baixa fica registrada com o seu nome.
          </DialogDescription>
        </DialogHeader>

        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">Voltar</Button>
          </DialogClose>
          <Button
            disabled={processing}
            onClick={() =>
              post(`/pedidos/${order.id}/pagamento`, { onSuccess: () => setOpen(false) })
            }
          >
            {processing ? "Registrando..." : "Confirmar pagamento"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

/**
 * Controle da entrega: para onde vai, quem está levando, o que já aconteceu e
 * o botão do estágio atual.
 *
 * A tela é a mesma para o balcão e para o entregador — muda o que cada um
 * pode fazer. Quem está no balcão despacha e conserta; quem está na rua marca
 * a saída e a chegada, e por isso esses dois botões são os grandes.
 */
const Delivery: React.FC<{ order: Order; drivers: Driver[] }> = ({ order, drivers }) => {
  const { post, processing } = useForm({});
  const { isDriver } = useAuth();
  const advance = (stage: string) => post(`/pedidos/${order.id}/entrega/${stage}`);

  const pending = order.deliveryStatus === "pending";

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between">
        <CardTitle className="text-sm">Entrega</CardTitle>
        <DeliveryBadge order={order} />
      </CardHeader>

      <CardContent className="space-y-4">
        <DeliveryAddress order={order} />

        <ol className="space-y-2 text-sm">
          <Step done label="Pedido registrado" at={order.insertedAt} />
          <Step
            done={order.driverId !== null}
            label={
              order.driverName
                ? `Enviado para ${order.driverName}`
                : "Aguardando um entregador"
            }
            at={order.assignedAt}
          />
          <Step
            done={order.deliveryStatus !== "pending"}
            label="Saiu para entrega"
            at={order.outForDeliveryAt}
          />
          <Step
            done={order.deliveryStatus === "delivered"}
            label="Entregue"
            at={order.deliveredAt}
          />
        </ol>

        {/* Despachar é do balcão, e só enquanto o pedido está na fila. */}
        {!isDriver && pending && (
          <DispatchDialog order={order} drivers={drivers} disabled={processing} />
        )}

        {pending && (
          <div className="grid gap-2">
            <Button size="lg" disabled={processing} onClick={() => advance("saiu")}>
              Saiu para entrega
            </Button>
            <Button
              variant="outline"
              size="sm"
              disabled={processing}
              onClick={() => advance("entregue")}
            >
              Já foi entregue
            </Button>
          </div>
        )}

        {order.deliveryStatus === "out_for_delivery" && (
          <Button
            size="lg"
            className="w-full"
            disabled={processing}
            onClick={() => advance("entregue")}
          >
            Confirmar entrega
          </Button>
        )}

        {/* Desfazer devolve o pedido à fila e tira o entregador — é conserto
            de marcação errada, e quem conserta é o balcão. */}
        {!isDriver && !pending && (
          <Button
            variant="ghost"
            size="sm"
            className="w-full text-muted-foreground"
            disabled={processing}
            onClick={() => advance("reabrir")}
          >
            Marquei sem querer, desfazer
          </Button>
        )}
      </CardContent>
    </Card>
  );
};

/**
 * Para onde vai o pedido. O mapa aparece quando o endereço foi localizado no
 * cadastro; o botão de rota abre o app de mapas do celular, que é onde o
 * entregador realmente navega.
 */
const DeliveryAddress: React.FC<{ order: Order }> = ({ order }) => {
  if (!order.deliveryAddress) return null;

  const located = order.deliveryLat !== null && order.deliveryLon !== null;

  return (
    <div className="space-y-2 rounded-lg border border-border bg-muted/50 p-3">
      <div className="flex items-start gap-2">
        <MapPin className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
        <p className="min-w-0 flex-1 text-sm">{order.deliveryAddress}</p>
      </div>

      {located && (
        <>
          <AddressMap
            lat={order.deliveryLat as number}
            lon={order.deliveryLon as number}
            label={order.deliveryAddress}
            className="h-44"
          />

          <Button asChild variant="outline" size="sm" className="w-full">
            <a
              href={`https://www.google.com/maps/dir/?api=1&destination=${order.deliveryLat},${order.deliveryLon}`}
              target="_blank"
              rel="noreferrer"
            >
              <Navigation className="size-4" />
              Traçar rota
            </a>
          </Button>
        </>
      )}
    </div>
  );
};

/**
 * Escolher para quem mandar o pedido pronto. É uma folha, e não um botão
 * direto, porque a escolha do entregador é uma decisão — e trocar depois
 * exige reabrir a entrega.
 */
const DispatchDialog: React.FC<{
  order: Order;
  drivers: Driver[];
  disabled: boolean;
}> = ({ order, drivers, disabled }) => {
  const [open, setOpen] = React.useState(false);
  const { data, setData, post, processing } = useForm({ driver_id: order.driverId ?? "" });

  if (drivers.length === 0) {
    return (
      <p className="rounded-lg border border-border p-3 text-xs text-muted-foreground">
        Nenhum entregador cadastrado. O admin cria o acesso em Equipe, com o
        perfil <strong className="text-foreground">Entregador</strong>.
      </p>
    );
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant={order.driverId ? "outline" : "default"} size="sm" className="w-full" disabled={disabled}>
          <Bike className="size-4" />
          {order.driverId ? "Trocar o entregador" : "Enviar para um entregador"}
        </Button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <DialogTitle>Quem leva o pedido {order.code}?</DialogTitle>
          <DialogDescription>
            O pedido aparece na hora na tela de entregas dessa pessoa, com o
            endereço e o mapa.
          </DialogDescription>
        </DialogHeader>

        <form
          className="space-y-4"
          onSubmit={(event) => {
            event.preventDefault();
            post(`/pedidos/${order.id}/entregador`, { onSuccess: () => setOpen(false) });
          }}
        >
          <Field label="Entregador" htmlFor="driver_id">
            <Select value={data.driver_id} onValueChange={(value) => setData("driver_id", value)}>
              <SelectTrigger id="driver_id" aria-label="Entregador">
                <SelectValue placeholder="Escolher quem leva" />
              </SelectTrigger>
              <SelectContent>
                {drivers.map((driver) => (
                  <SelectItem key={driver.id} value={driver.id}>
                    {driver.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" size="sm">
                Voltar
              </Button>
            </DialogClose>
            <Button type="submit" size="sm" disabled={processing || data.driver_id === ""}>
              {processing ? "Enviando..." : "Enviar"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};

const Step: React.FC<{ label: string; at?: string | null; done: boolean }> = ({
  label,
  at,
  done,
}) => (
  <li className="flex items-center gap-3">
    <span
      className={
        done
          ? "size-2.5 shrink-0 rounded-full bg-primary"
          : "size-2.5 shrink-0 rounded-full border border-border"
      }
    />
    <span className={done ? "font-medium" : "text-muted-foreground"}>{label}</span>
    {at && (
      <span className="ml-auto text-xs tabular-nums text-muted-foreground">
        {dateTimeLabel(at)}
      </span>
    )}
  </li>
);

const Row: React.FC<{ label: string; value: React.ReactNode }> = ({ label, value }) => (
  <div className="flex items-center justify-between gap-3">
    <span className="text-muted-foreground">{label}</span>
    <span className="text-right font-medium">{value}</span>
  </div>
);

/**
 * Cancelamento pede um motivo, então é um Dialog com formulário — não um
 * AlertDialog de sim/não.
 */
const CancelDialog: React.FC<{ order: Order }> = ({ order }) => {
  const [open, setOpen] = React.useState(false);
  const { data, setData, post, processing } = useForm({ reason: "" });

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" className="w-full text-destructive">
          Cancelar pedido
        </Button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <DialogTitle>Cancelar o pedido {order.code}?</DialogTitle>
          <DialogDescription>
            Os {order.items?.length ?? 0} itens voltam para o estoque. Isso não pode ser
            desfeito.
          </DialogDescription>
        </DialogHeader>

        <form
          className="space-y-4"
          onSubmit={(event) => {
            event.preventDefault();
            post(`/pedidos/${order.id}/cancelar`, {
              onSuccess: () => setOpen(false),
            });
          }}
        >
          <Field label="Motivo" htmlFor="reason" hint="Fica registrado no histórico do estoque.">
            <Textarea
              id="reason"
              rows={2}
              placeholder="Cliente desistiu, peso errado..."
              value={data.reason}
              onChange={(e) => setData("reason", e.target.value)}
            />
          </Field>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Voltar</Button>
            </DialogClose>
            <Button type="submit" variant="destructive" disabled={processing}>
              {processing ? "Cancelando..." : "Cancelar pedido"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};
