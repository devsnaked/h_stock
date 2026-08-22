defmodule Core.Inventory.StockMovement do
  @moduledoc """
  Histórico do estoque: uma linha por entrada, saída ou ajuste.

  `grams` é **assinado** — positivo entra, negativo sai — então o saldo de um
  produto é a soma das suas movimentações. `kind` é só o rótulo que explica o
  motivo do sinal.

  Toda movimentação aponta para o lote (`batch`) que ela mexeu, e guarda o
  custo daquele lote no momento (`cost_per_gram`, `total_cost`). É esse par
  que transforma o histórico em dinheiro: quanto entrou de mercadoria comprada
  e quanto saiu de custo em cada venda.

  Movimentações não são criadas diretamente: elas nascem das ações de estoque
  do `Core.Inventory.Product`, dentro da mesma transação que altera o saldo.
  """
  use Ash.Resource,
    otp_app: :h_stock,
    domain: Core.Inventory,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "stock_movements"
    repo Core.Repo

    references do
      reference :product, on_delete: :delete
      reference :batch, on_delete: :delete
      reference :order, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :kind,
        :grams,
        :balance_after,
        :batch_balance_after,
        :cost_per_gram,
        :total_cost,
        :reason,
        :product_id,
        :batch_id,
        :user_id,
        :order_id
      ]
    end

    read :for_product do
      description """
      Histórico de um produto, do mais novo para o mais antigo.

      Paginado porque um produto que gira acumula centenas de linhas — e a
      tela mostra vinte por vez. `required? false`: quem quiser o histórico
      inteiro (um relatório, por exemplo) continua lendo sem pedir página.
      """

      argument :product_id, :uuid, allow_nil?: false

      filter expr(product_id == ^arg(:product_id))
      prepare build(sort: [inserted_at: :desc], load: [:user, :batch])

      pagination offset?: true, default_limit: 20, countable: true, required?: false
    end
  end

  policies do
    # O histórico é informação de estoque: só quem gerencia estoque enxerga.
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:can_manage_stock, true)
    end

    # Criação só acontece por dentro das ações do produto, que rodam com
    # `authorize?: false` depois de já terem validado a permissão.
    policy action_type(:create) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      constraints one_of: [:in, :out, :adjustment]
      allow_nil? false
      public? true
    end

    attribute :grams, :decimal do
      description "Assinado: positivo entra no estoque, negativo sai."
      allow_nil? false
      public? true
    end

    attribute :balance_after, :decimal do
      description "Saldo do produto depois desta movimentação."
      allow_nil? false
      public? true
    end

    attribute :batch_balance_after, :decimal do
      description "Saldo do lote depois desta movimentação."
      public? true
    end

    attribute :cost_per_gram, :decimal do
      description "Custo da grama no lote movimentado."
      public? true
    end

    attribute :total_cost, :decimal do
      description "Dinheiro que esta movimentação pôs (ou tirou) do estoque. Assinado como `grams`."
      public? true
    end

    attribute :reason, :string do
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :product, Core.Inventory.Product do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :batch, Core.Inventory.Batch do
      description "Lote movimentado."
      attribute_writable? true
    end

    belongs_to :user, Core.Accounts.User do
      description "Quem provocou a movimentação."
      attribute_writable? true
    end

    belongs_to :order, Core.Orders.Order do
      description "Preenchido quando a movimentação veio de um pedido."
      attribute_writable? true
    end
  end
end
