defmodule Core.Orders.OrderItem do
  @moduledoc """
  Linha de um pedido.

  `product_name`, `price_per_gram`, `batch_label` e `cost_per_gram` são cópias
  do produto e do lote no momento da venda: o histórico precisa continuar
  verdadeiro mesmo depois de o produto mudar de preço, de nome, de o lote
  acabar ou de o produto ser desativado.

  É o par `price_per_gram` × `cost_per_gram` que dá o lucro da linha — por
  isso a venda diz de qual lote saiu a mercadoria.
  """
  use Ash.Resource,
    otp_app: :h_stock,
    domain: Core.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "order_items"
    repo Core.Repo

    references do
      reference :order, on_delete: :delete
      reference :product, on_delete: :restrict
      reference :batch, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :product_name,
        :grams,
        :price_per_gram,
        :total,
        :batch_label,
        :cost_per_gram,
        :total_cost,
        :product_id,
        :batch_id,
        :order_id
      ]
    end
  end

  policies do
    # Mesma régua do pedido a que o item pertence: quem alcança o pedido
    # alcança o que tem dentro dele. O entregador entra por
    # `order.driver_id` — ele precisa conferir o que vai na sacola.
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:can_manage_orders, true)
      authorize_if expr(order.user_id == ^actor(:id))
      authorize_if expr(order.driver_id == ^actor(:id))
    end

    # Itens só são criados junto do pedido, pela ação `:register`.
    policy action_type(:create) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :product_name, :string do
      allow_nil? false
      public? true
    end

    attribute :grams, :decimal do
      allow_nil? false
      public? true
      constraints greater_than: 0
    end

    attribute :price_per_gram, :decimal do
      allow_nil? false
      public? true
      constraints min: 0
    end

    attribute :total, :decimal do
      allow_nil? false
      public? true
      constraints min: 0
    end

    attribute :batch_label, :string do
      description "Nome do lote de onde a mercadoria saiu, congelado na venda."
      public? true
    end

    attribute :cost_per_gram, :decimal do
      description "Custo da grama no lote vendido."
      allow_nil? false
      public? true
      default Decimal.new(0)
      constraints min: 0
    end

    attribute :total_cost, :decimal do
      description "O que esta linha custou: `grams` × `cost_per_gram`."
      allow_nil? false
      public? true
      default Decimal.new(0)
      constraints min: 0
    end
  end

  relationships do
    belongs_to :order, Core.Orders.Order do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :product, Core.Inventory.Product do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :batch, Core.Inventory.Batch do
      description "Lote vendido. É para ele que a mercadoria volta no cancelamento."
      attribute_writable? true
    end
  end

  calculations do
    calculate :profit, :decimal, expr(total - total_cost) do
      description "Lucro bruto da linha, antes do desconto do pedido."
      public? true
    end
  end
end
