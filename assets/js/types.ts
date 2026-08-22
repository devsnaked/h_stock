/** Unidade em que peso é digitado/exibido. Internamente tudo é grama. */
export type Unit = "g" | "kg";

/**
 * `driver` é o entregador: recebe pedidos prontos e marca a entrega. Não
 * vende, não vê estoque e não abre as telas de balcão.
 */
export type Role = "admin" | "employee" | "driver";

/**
 * Uma seção de dados do painel. Cada uma é uma permissão à parte
 * (`Core.Accounts.Permissions`) e o nome é o mesmo do prop que a carrega — o
 * bloco pede `sales` ao servidor e recebe `sales`.
 */
export type DashboardSection =
  | "sales"
  | "hours"
  | "products"
  | "team"
  | "delivery"
  | "stock"
  | "recent";

/** Usuário autenticado, como serializado por `Web.Serializers.user/1`. */
export type User = {
  id: string;
  name: string;
  /** Login da pessoa. Não há e-mail no sistema. */
  nickname: string;
  role: Role;
  canManageStock: boolean;
  /** admin OU funcionário com permissão — é o que a UI deve checar. */
  managesStock: boolean;
  /** Alcança os pedidos da equipe inteira, não só os que registrou. */
  canManageOrders: boolean;
  managesOrders: boolean;
  /** Chave do painel, como está guardada — é dela que o formulário parte. */
  canViewDashboard: boolean;
  /** admin OU quem foi liberado — é o que a navegação deve checar. */
  viewsDashboard: boolean;
  /**
   * Seções liberadas, como estão guardadas. Para o admin a lista pode estar
   * vazia e ele ainda vê tudo; quem manda no painel é o prop `sections` da
   * própria página.
   */
  dashboardSections: DashboardSection[];
  active: boolean;
  /** Verificação em duas etapas ligada nesta conta. */
  twoFactor: boolean;
  insertedAt?: string;
};

export type Product = {
  id: string;
  name: string;
  unit: Unit;
  pricePerGram: number;
  pricePerKg: number;
  stockGrams: number;
  minStockGrams: number;
  lowStock: boolean;
  active: boolean;
  /** Dinheiro parado no estoque. Só vem para quem gerencia estoque. */
  stockCostValue?: number;
  /** Lotes com saldo. Só a tela de novo pedido recebe. */
  batches?: Batch[];
};

/**
 * Lote de mercadoria: uma compra, com o custo dela. Lotes não se misturam —
 * toda saída diz de qual lote está saindo.
 *
 * Os campos de custo só chegam para quem gerencia estoque; para o resto da
 * casa o lote é só um nome e um saldo.
 */
export type Batch = {
  id: string;
  label: string;
  remainingGrams: number;
  initialGrams: number;
  depleted: boolean;
  insertedAt: string;
  userName: string | null;
  costPerGram?: number;
  costPerKg?: number;
  /** Custo do que ainda há no lote. */
  remainingCost?: number;
  /** Custo da compra inteira. */
  totalCost?: number;
};

export type MovementKind = "in" | "out" | "adjustment";

export type StockMovement = {
  id: string;
  kind: MovementKind;
  /** Assinado: positivo entrou, negativo saiu. */
  grams: number;
  balanceAfter: number;
  batchBalanceAfter: number | null;
  costPerGram: number | null;
  /** Assinado como `grams`: o dinheiro que entrou ou saiu do estoque. */
  totalCost: number | null;
  batchId: string | null;
  batchLabel: string | null;
  reason: string | null;
  insertedAt: string;
  userName: string | null;
  /** Pedido que gerou a movimentação — venda e devolução de cancelamento. */
  orderId: string | null;
  /** Código curto do pedido, derivado do id (`Core.Orders.code/1`). */
  orderCode: string | null;
};

export type DiscountType = "none" | "percent" | "amount";

/**
 * Estágio da entrega, independente de `status` (que diz se a venda vale).
 * `not_required` é retirada no balcão — não entra na fila de entrega.
 */
export type DeliveryStatus =
  | "not_required"
  | "pending"
  | "out_for_delivery"
  | "delivered";

export type OrderItem = {
  id: string;
  productId: string;
  productName: string;
  grams: number;
  pricePerGram: number;
  total: number;
  batchId: string | null;
  /** Nome do lote no dia da venda. */
  batchLabel: string | null;
  costPerGram?: number;
  totalCost?: number;
  profit?: number;
};

export type Order = {
  id: string;
  code: string;
  customerName: string | null;
  status: "completed" | "cancelled";
  subtotal: number;
  discountType: DiscountType;
  discountValue: number;
  discountTotal: number;
  total: number;
  insertedAt: string;
  cancelledAt: string | null;
  deliveryStatus: DeliveryStatus;
  /** Endereço escrito no balcão. Só existe em pedido com entrega. */
  deliveryAddress: string | null;
  /** Coordenadas do endereço, quando a busca no mapa achou. */
  deliveryLat: number | null;
  deliveryLon: number | null;
  driverId: string | null;
  driverName: string | null;
  /** Quando o pedido foi mandado para o entregador. */
  assignedAt: string | null;
  outForDeliveryAt: string | null;
  deliveredAt: string | null;
  userName: string | null;
  itemsCount?: number;
  note?: string | null;
  items?: OrderItem[];
  /** Custo e lucro só chegam para quem gerencia estoque. */
  costTotal?: number;
  profit?: number;
};

/** Entregador na lista de para quem mandar o pedido. */
export type Driver = {
  id: string;
  name: string;
  nickname: string;
};

/** Um ponto no mapa devolvido pela busca de endereço (Nominatim). */
export type Place = {
  label: string;
  lat: number;
  lon: number;
};

/**
 * Os números do painel, uma categoria por vez (`Core.Analytics`).
 *
 * Cada uma chega numa requisição própria, quando o bloco correspondente entra
 * na tela — por isso são tipos separados, e não um objetão só. Lucro e custo
 * só existem para quem gerencia estoque, daí os campos opcionais.
 */
export type SalesAnalytics = {
  daily: {
    date: string;
    orders: number;
    revenue: number;
    discount: number;
    cost?: number;
    profit?: number;
  }[];
  totals: {
    orders: number;
    revenue: number;
    discount: number;
    /** Faturamento dividido pelos pedidos do período. */
    ticket: number;
    cost?: number;
    profit?: number;
  };
  cancellations: { count: number; total: number };
};

export type HourAnalytics = { hour: number; orders: number; revenue: number };

export type ProductAnalytics = {
  name: string;
  grams: number;
  revenue: number;
  orders: number;
  profit?: number;
};

export type TeamAnalytics = { name: string; orders: number; revenue: number };

export type DeliveryAnalytics = {
  /** A rua agora — independe do período escolhido. */
  now: { toDeliver: number; deliveredToday: number };
  summary: {
    pending: number;
    outForDelivery: number;
    delivered: number;
    pickup: number;
    /** Pedidos prontos sem entregador definido. */
    unassigned: number;
    /** Média do registro à entrega, em minutos. `null` sem entrega no período. */
    averageMinutes: number | null;
  };
  drivers: {
    name: string;
    assigned: number;
    delivered: number;
    onTheWay: number;
    averageMinutes: number | null;
  }[];
};

export type StockAnalytics = {
  active: number;
  low: number;
  lowProducts: { id: string; name: string; stockGrams: number }[];
  value?: number;
  topValue?: { name: string; value: number }[];
};

/** Props que o backend publica em TODA página (ver `SetCurrentUser`). */
export type SharedProps = {
  user: User | null;
  csrfToken: string;
  flash?: Record<string, string>;
  errors?: Record<string, string>;
};
