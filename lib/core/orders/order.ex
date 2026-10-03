defmodule Core.Orders.Order do
  @moduledoc """
  Venda registrada por um funcionário.

  Os totais (`subtotal`, `discount_total`, `total`, `cost_total`) são sempre
  calculados no servidor a partir dos itens e do desconto — o que o cliente
  manda é apenas produto, lote, peso e o desconto pedido. Ver
  `Core.Orders.Changes.BuildOrder`.

  O custo vem do lote escolhido em cada item, congelado na venda; é dele que
  sai o `profit`.

  **Venda a prazo** é a que nasce com `payment_due_on` (o dia combinado com o
  cliente). Sem ele, a venda é à vista: foi paga no balcão, e não há o que
  receber. Um pedido a prazo fica em aberto (`paid_at` vazio) até alguém do
  balcão dizer que o dinheiro entrou (`:mark_paid`) — e vencido quando o dia
  combinado passa sem isso. O "hoje" do vencimento é o da loja
  (`Core.Clock`).
  """
  use Ash.Resource,
    otp_app: :h_stock,
    domain: Core.Orders,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  sqlite do
    table "orders"
    repo Core.Repo

    references do
      reference :user, on_delete: :restrict
      reference :driver, on_delete: :nilify
      reference :edited_by, on_delete: :nilify
    end
  end

  actions do
    read :read do
      primary? true

      description """
      Leitura paginada. `required? false` de propósito: a lista de pedidos
      pede página, mas o painel e os relatórios varrem o período inteiro e
      continuam recebendo uma lista simples.
      """

      pagination offset?: true, default_limit: 20, countable: true, required?: false
    end

    read :mine do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
    end

    read :to_deliver do
      description "Fila de entrega: o que já foi vendido e ainda não chegou."

      filter expr(
               status == :completed and
                 delivery_status in [:pending, :out_for_delivery]
             )
    end

    read :for_driver do
      description "As entregas de um entregador: o que está com ele agora."

      argument :driver_id, :uuid, allow_nil?: false

      filter expr(
               driver_id == ^arg(:driver_id) and status == :completed and
                 delivery_status in [:pending, :out_for_delivery]
             )
    end

    create :register do
      description "Registra a venda e dá baixa no estoque."

      accept [
        :customer_name,
        :note,
        :discount_type,
        :discount_value,
        :delivery_status,
        :delivery_address,
        :delivery_lat,
        :delivery_lon,
        :payment_due_on
      ]

      # Um pedido nasce esperando entrega ou sem entrega nenhuma (retirada no
      # balcão). "Saiu" e "entregue" são passos posteriores, com hora própria.
      validate one_of(:delivery_status, [:pending, :not_required])

      # Combinar o pagamento para ontem é erro de digitação: a venda a prazo
      # já nasceria vencida.
      validate compare(:payment_due_on, greater_than_or_equal_to: &Core.Clock.today/0) do
        message "a data do pagamento não pode ser no passado"
      end

      # Dívida sem devedor não se cobra: a venda a prazo precisa dizer quem
      # vai pagar.
      validate present(:customer_name),
        where: [present(:payment_due_on)],
        message: "venda a prazo precisa do nome do cliente"

      argument :items, {:array, :map} do
        description "Lista de `%{product_id: uuid, batch_id: uuid, grams: decimal}`."
        allow_nil? false
        constraints min_length: 1
      end

      argument :driver_id, :uuid do
        description """
        Entregador que já sai com o pedido. Opcional: vazio quer dizer que a
        venda entra na fila sem dono, e alguém despacha depois.
        """
      end

      change relate_actor(:user)
      change Core.Orders.Changes.AssignDriver
      change Core.Orders.Changes.BuildOrder
      change {Core.Orders.Changes.LogOrderEvent, action: :order_registered}
    end

    update :assign_driver do
      description "Pedido pronto: manda para um entregador."
      require_atomic? false
      accept []

      argument :driver_id, :uuid, allow_nil?: false

      validate attribute_equals(:status, :completed) do
        message "pedido cancelado não vai para entrega"
      end

      # Só enquanto está na fila. Depois de sair, trocar o entregador seria
      # dizer que a mercadoria mudou de mão no meio da rua — para isso o
      # caminho é reabrir a entrega e mandar de novo.
      validate attribute_equals(:delivery_status, :pending) do
        message "este pedido não está mais aguardando saída"
      end

      change Core.Orders.Changes.AssignDriver
      change {Core.Orders.Changes.LogOrderEvent, action: :order_driver_assigned}
    end

    update :mark_out_for_delivery do
      # O log descreve o pedido depois da ação (quem é o entregador, para onde
      # vai), e ler o registro é o que o update atômico dispensa fazer.
      require_atomic? false

      description "O pedido saiu para entrega."
      accept []

      validate attribute_equals(:status, :completed) do
        message "pedido cancelado não sai para entrega"
      end

      validate attribute_equals(:delivery_status, :pending) do
        message "este pedido não está aguardando saída"
      end

      change set_attribute(:delivery_status, :out_for_delivery)
      change set_attribute(:out_for_delivery_at, &DateTime.utc_now/0)
      change {Core.Orders.Changes.LogOrderEvent, action: :order_out_for_delivery}
    end

    update :mark_delivered do
      # O log descreve o pedido depois da ação (quem é o entregador, para onde
      # vai), e ler o registro é o que o update atômico dispensa fazer.
      require_atomic? false

      description "O pedido chegou ao cliente."
      accept []

      validate attribute_equals(:status, :completed) do
        message "pedido cancelado não pode ser entregue"
      end

      # Aceita marcar direto de `:pending`: no corre-corre o entregador
      # esquece de avisar a saída, e forçar dois toques só faria a pessoa
      # deixar de registrar a entrega.
      validate attribute_in(:delivery_status, [:pending, :out_for_delivery]) do
        message "este pedido já foi entregue"
      end

      change set_attribute(:delivery_status, :delivered)
      change set_attribute(:delivered_at, &DateTime.utc_now/0)
      change {Core.Orders.Changes.LogOrderEvent, action: :order_delivered}
    end

    update :reopen_delivery do
      # O log descreve o pedido depois da ação (quem é o entregador, para onde
      # vai), e ler o registro é o que o update atômico dispensa fazer.
      require_atomic? false

      description "Desfaz a marcação de entrega (registrada por engano)."
      accept []

      validate attribute_in(:delivery_status, [:out_for_delivery, :delivered]) do
        message "este pedido já está aguardando saída"
      end

      change set_attribute(:delivery_status, :pending)
      change set_attribute(:out_for_delivery_at, nil)
      change set_attribute(:delivered_at, nil)

      # Volta para a fila sem dono: quem reabre decide de novo para quem
      # manda, e o pedido some da lista do entregador anterior.
      change set_attribute(:driver_id, nil)
      change set_attribute(:assigned_at, nil)
      change {Core.Orders.Changes.LogOrderEvent, action: :order_reopened}
    end

    update :cancel do
      description "Cancela a venda e devolve os itens ao estoque."
      require_atomic? false
      accept []

      argument :reason, :string

      validate attribute_equals(:status, :completed) do
        message "este pedido já foi cancelado"
      end

      change set_attribute(:status, :cancelled)
      change set_attribute(:cancelled_at, &DateTime.utc_now/0)
      change Core.Orders.Changes.ReturnStock
      change {Core.Orders.Changes.LogOrderEvent, action: :order_cancelled}
    end

    update :mark_paid do
      # O log descreve o pedido depois da ação, e ler o registro é o que o
      # update atômico dispensa fazer.
      require_atomic? false

      description "Venda a prazo: o cliente pagou."
      accept []

      validate attribute_equals(:status, :completed) do
        message "pedido cancelado não tem o que receber"
      end

      validate present(:payment_due_on) do
        message "este pedido foi pago à vista"
      end

      validate absent(:paid_at) do
        message "este pedido já está pago"
      end

      # Baixa e linha do log são uma escrita só: dívida quitada sem registro
      # de quem recebeu é o buraco que o log existe para fechar.
      change Core.Changes.InTransaction
      change set_attribute(:paid_at, &DateTime.utc_now/0)
      change {Core.Orders.Changes.LogOrderEvent, action: :order_paid}
    end

    update :edit do
      description """
      Corrige o pedido: cliente, observação, endereço, forma de pagamento e
      os itens (peso, incluir, tirar) — com o estoque acompanhando lote a
      lote. O desconto continua o que era, refeito sobre o novo subtotal.
      """

      # O log compara o pedido antes e depois, e ler o registro é o que o
      # update atômico dispensa fazer.
      require_atomic? false

      accept [
        :customer_name,
        :note,
        :delivery_address,
        :delivery_lat,
        :delivery_lon,
        :payment_due_on
      ]

      argument :items, {:array, :map} do
        description """
        Lista final dos itens. `%{id, grams}` para linha que já estava,
        `%{product_id, batch_id, grams}` para linha nova. Ausente: itens não
        mudam. Ver `Core.Orders.Changes.EditItems`.
        """
      end

      validate attribute_equals(:status, :completed) do
        message "pedido cancelado não pode ser editado"
      end

      # Retirada no balcão não tem para onde ir.
      validate absent([:delivery_address, :delivery_lat, :delivery_lon]),
        where: [attribute_equals(:delivery_status, :not_required)],
        message: "pedido de retirada no balcão não tem endereço"

      # Depois da baixa, a forma de pagamento é história: trocar o vencimento
      # de uma conta já paga reescreveria se ela foi paga em dia.
      validate absent(:paid_at),
        where: [changing(:payment_due_on)],
        message: "o pagamento já foi registrado; a forma de pagamento não muda mais"

      # Só o vencimento que muda precisa ser de hoje em diante: editar a
      # observação de uma conta vencida não pode ser recusado por ela estar
      # vencida.
      validate compare(:payment_due_on, greater_than_or_equal_to: &Core.Clock.today/0),
        where: [changing(:payment_due_on)],
        message: "a data do pagamento não pode ser no passado"

      validate present(:customer_name),
        where: [present(:payment_due_on)],
        message: "venda a prazo precisa do nome do cliente"

      # Edição, itens, estoque e linha do log são uma escrita só: pedido
      # alterado sem o estoque acompanhar, ou sem registro de quem alterou e
      # do que havia antes, é o que isto impede.
      change Core.Changes.InTransaction
      change Core.Orders.Changes.EditItems
      change Core.Orders.Changes.MarkEdited
      change {Core.Orders.Changes.LogOrderEvent, action: :order_updated}
    end
  end

  policies do
    # Quem enxerga o quê: admin e quem tem `can_manage_orders` veem a loja
    # inteira; o funcionário comum, os pedidos que ele registrou; o
    # entregador, apenas os que estão na mão dele.
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:can_manage_orders, true)
      authorize_if expr(user_id == ^actor(:id))
      authorize_if expr(driver_id == ^actor(:id))
    end

    # Entregador não vende: o app dele é a lista de entregas.
    policy action(:register) do
      forbid_if actor_attribute_equals(:role, :driver)
      authorize_if actor_present()
    end

    # Cancelar é do admin, de quem gerencia pedidos, ou de quem registrou
    # (para corrigir o próprio erro).
    policy action(:cancel) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:can_manage_orders, true)
      authorize_if expr(user_id == ^actor(:id))
    end

    # Despachar e reabrir são do balcão — o entregador recebe o pedido, não
    # decide quem o leva.
    policy action([:assign_driver, :reopen_delivery]) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:can_manage_orders, true)
      authorize_if expr(user_id == ^actor(:id))
    end

    # Receber e editar são do balcão, com a mesma régua de cancelar: quem
    # registrou a venda ou quem alcança os pedidos da equipe. O entregador
    # leva a mercadoria, não dá baixa em dívida nem reescreve o pedido.
    policy action([:mark_paid, :edit]) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:can_manage_orders, true)
      authorize_if expr(user_id == ^actor(:id))
    end

    # Saída e entrega são de quem está com a mercadoria na mão: o entregador a
    # quem o pedido foi mandado, e também o balcão (nem toda venda vai para a
    # rua com entregador, e a retirada continua sendo marcada aqui).
    policy action([:mark_out_for_delivery, :mark_delivered]) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:can_manage_orders, true)
      authorize_if expr(driver_id == ^actor(:id))
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :customer_name, :string do
      public? true
      constraints trim?: true
    end

    attribute :note, :string do
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:completed, :cancelled]
      default :completed
      allow_nil? false
      public? true
    end

    attribute :discount_type, :atom do
      constraints one_of: [:none, :percent, :amount]
      default :none
      allow_nil? false
      public? true
    end

    attribute :discount_value, :decimal do
      description "Porcentagem (0–100) ou valor em reais, conforme `discount_type`."
      default Decimal.new(0)
      allow_nil? false
      public? true
      constraints min: 0
    end

    attribute :subtotal, :decimal do
      allow_nil? false
      public? true
      default Decimal.new(0)
      writable? false
    end

    attribute :discount_total, :decimal do
      allow_nil? false
      public? true
      default Decimal.new(0)
      writable? false
    end

    attribute :total, :decimal do
      allow_nil? false
      public? true
      default Decimal.new(0)
      writable? false
    end

    attribute :cost_total, :decimal do
      description """
      O que a mercadoria vendida custou, somando o custo do lote de cada item.
      Congelado na venda: mudar o custo de um lote depois não reescreve o
      lucro de um pedido antigo.
      """

      allow_nil? false
      public? true
      default Decimal.new(0)
      writable? false
    end

    attribute :cancelled_at, :utc_datetime_usec do
      public? true
    end

    @doc """
    Estágio da entrega, independente de `status` (que diz se a venda vale).

      * `:not_required` — retirada no balcão, não entra na fila de entrega;
      * `:pending` — vendido, aguardando sair;
      * `:out_for_delivery` — a caminho;
      * `:delivered` — chegou.
    """
    attribute :delivery_status, :atom do
      constraints one_of: [:not_required, :pending, :out_for_delivery, :delivered]
      default :pending
      allow_nil? false
      public? true
    end

    # Endereço da entrega, como foi escrito no balcão. Fica no pedido (e não
    # num cadastro de cliente, que não existe aqui): a mesma pessoa pede hoje
    # para casa e amanhã para o trabalho.
    attribute :delivery_address, :string do
      public? true
      constraints trim?: true, max_length: 300
    end

    # Coordenadas do endereço, quando a geocodificação achou. Guardadas junto
    # do pedido para o entregador abrir o mapa sem depender de o serviço
    # externo responder de novo.
    attribute :delivery_lat, :decimal do
      public? true
      constraints min: -90, max: 90
    end

    attribute :delivery_lon, :decimal do
      public? true
      constraints min: -180, max: 180
    end

    attribute :assigned_at, :utc_datetime_usec do
      description "Quando o pedido foi mandado para o entregador."
      public? true
    end

    attribute :out_for_delivery_at, :utc_datetime_usec do
      public? true
    end

    attribute :delivered_at, :utc_datetime_usec do
      public? true
    end

    # Pagamento. Vazio é venda à vista — paga no balcão, nada a receber.
    # Preenchido, é o dia combinado com o cliente, no calendário da loja.
    attribute :payment_due_on, :date do
      description "Vencimento da venda a prazo. Vazio: venda à vista."
      public? true
    end

    attribute :paid_at, :utc_datetime_usec do
      description "Quando a venda a prazo foi paga. Vazio: em aberto."
      public? true
    end

    attribute :edited_at, :utc_datetime_usec do
      description "Última edição (`:edit`) que de fato mudou alguma coisa."
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Core.Accounts.User do
      description "Funcionário que registrou a venda."
      allow_nil? false
    end

    belongs_to :driver, Core.Accounts.User do
      description "Entregador que recebeu o pedido. Vazio enquanto está na fila."
      allow_nil? true
    end

    belongs_to :edited_by, Core.Accounts.User do
      description """
      Quem fez a última edição. O histórico completo — cada edição, com o
      que havia antes — está no log de auditoria.
      """

      allow_nil? true
    end

    has_many :items, Core.Orders.OrderItem
  end

  calculations do
    calculate :profit,
              :decimal,
              {Core.Calculations.Arithmetic, sub: [:total, :cost_total]} do
      description "O que sobrou da venda: total (já com desconto) menos o custo."
      public? true
    end

    calculate :total_grams,
              :decimal,
              {Core.Calculations.Rollup, relationship: :items, field: :grams}

    calculate :items_count, :integer, {Core.Calculations.Rollup, relationship: :items}
  end
end
