defmodule Core.Inventory.Product do
  @moduledoc """
  Produto vendido a peso.

  `stock_grams` é um saldo em cache: quem manda são os lotes
  (`Core.Inventory.Batch`), cada um com o seu custo e o seu saldo. Por isso o
  campo não é aceito em `:create` nem em `:update` — só as ações de estoque o
  alteram, e sempre mexendo num lote e gravando a movimentação junto.

  Entrada abre um lote novo (com custo); saída, devolução e ajuste sempre
  dizem de qual lote estão falando.
  """
  use Ash.Resource,
    otp_app: :h_stock,
    domain: Core.Inventory,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "products"
    repo Core.Repo
  end

  actions do
    defaults [:read]

    read :active do
      description "Só os produtos à venda."
      filter expr(active == true)
    end

    create :create do
      primary? true
      accept [:name, :unit, :price_per_gram, :min_stock_grams, :active]

      argument :initial_stock_grams, :decimal do
        description "Saldo inicial. Vira o primeiro lote."
        constraints min: 0
        default Decimal.new(0)
      end

      argument :initial_cost_per_gram, :decimal do
        description "Quanto custou a grama do saldo inicial."
        constraints min: 0
        default Decimal.new(0)
      end

      argument :initial_batch_label, :string do
        description "Nome do primeiro lote. Em branco vira \"Lote de DD/MM\"."
      end

      change Core.Inventory.Changes.SetInitialStock
    end

    update :update do
      primary? true
      accept [:name, :unit, :price_per_gram, :min_stock_grams, :active]
    end

    update :add_stock do
      description "Entrada de mercadoria: abre um lote novo com o custo pago."
      require_atomic? false
      accept []

      argument :grams, :decimal, allow_nil?: false, constraints: [greater_than: 0]

      argument :cost_per_gram, :decimal do
        description "Custo da grama nesta compra. É o que vira lucro na venda."
        allow_nil? false
        constraints min: 0
      end

      argument :label, :string do
        description "Como chamar o lote. Em branco vira \"Lote de DD/MM\"."
      end

      argument :reason, :string

      change {Core.Inventory.Changes.ApplyStockChange, kind: :in}
    end

    update :remove_stock do
      description "Saída de mercadoria (venda, perda, uso interno) de um lote."
      require_atomic? false
      accept []

      argument :grams, :decimal, allow_nil?: false, constraints: [greater_than: 0]
      argument :batch_id, :uuid, allow_nil?: false
      argument :reason, :string
      argument :order_id, :uuid

      change {Core.Inventory.Changes.ApplyStockChange, kind: :out}
    end

    update :return_stock do
      description """
      Devolve mercadoria ao lote de onde ela saiu — é o cancelamento de pedido.
      Não abre lote novo: o custo daquela venda tem de continuar sendo o mesmo.
      """

      require_atomic? false
      accept []

      argument :grams, :decimal, allow_nil?: false, constraints: [greater_than: 0]
      argument :batch_id, :uuid, allow_nil?: false
      argument :reason, :string
      argument :order_id, :uuid

      change {Core.Inventory.Changes.ApplyStockChange, kind: :return}
    end

    update :adjust_stock do
      description "Ajuste: define o saldo de um lote e registra a diferença."
      require_atomic? false
      accept []

      argument :grams, :decimal, allow_nil?: false, constraints: [min: 0]
      argument :batch_id, :uuid, allow_nil?: false
      argument :reason, :string

      change {Core.Inventory.Changes.ApplyStockChange, kind: :adjustment}
    end
  end

  policies do
    # Qualquer usuário autenticado precisa ler o catálogo para montar pedidos.
    policy action_type(:read) do
      authorize_if actor_present()
    end

    # Escrita é do admin ou de quem ele autorizou a mexer no estoque.
    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:can_manage_stock, true)
    end
  end

  validations do
    validate compare(:price_per_gram, greater_than: 0),
      message: "deve ser maior que zero",
      on: [:create, :update]
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 2, trim?: true
    end

    @doc "Unidade em que o produto é digitado/exibido. O preço é sempre por grama."
    attribute :unit, :atom do
      constraints one_of: [:g, :kg]
      default :kg
      allow_nil? false
      public? true
    end

    attribute :price_per_gram, :decimal do
      allow_nil? false
      public? true
      constraints min: 0
    end

    attribute :stock_grams, :decimal do
      allow_nil? false
      public? true
      default Decimal.new(0)
      writable? false
    end

    attribute :min_stock_grams, :decimal do
      description "Abaixo disso o produto aparece como estoque baixo."
      allow_nil? false
      public? true
      default Decimal.new(0)
      constraints min: 0
    end

    attribute :active, :boolean do
      default true
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :movements, Core.Inventory.StockMovement do
      sort inserted_at: :desc
    end

    has_many :batches, Core.Inventory.Batch do
      sort inserted_at: :asc
    end

    has_many :open_batches, Core.Inventory.Batch do
      description "Lotes com saldo — os que ainda dá para vender."
      filter expr(remaining_grams > 0)
      sort inserted_at: :asc
    end
  end

  calculations do
    calculate :price_per_kg, :decimal, expr(price_per_gram * 1000) do
      public? true
    end

    calculate :low_stock?, :boolean, expr(stock_grams <= min_stock_grams) do
      public? true
    end
  end

  aggregates do
    sum :stock_cost_value, :batches, :remaining_cost do
      description "Dinheiro parado no estoque: soma do que sobrou de cada lote."
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
