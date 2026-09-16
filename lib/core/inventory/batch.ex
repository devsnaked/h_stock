defmodule Core.Inventory.Batch do
  @moduledoc """
  Lote de mercadoria: uma compra que entrou no estoque, com o custo que ela
  teve.

  Lotes **não se misturam**. Duas caixas de laranja compradas por preços
  diferentes são dois lotes, cada um com o seu `cost_per_gram` e o seu saldo
  (`remaining_grams`). Toda saída — venda, perda, uso interno — diz de qual
  lote está saindo, e é o custo daquele lote que entra no cálculo do lucro.

  O saldo do produto (`Product.stock_grams`) é a soma dos lotes; quem manda é
  o lote. Como o histórico precisa continuar verdadeiro, lote nunca é apagado:
  quando zera, ganha `depleted_at` e some das telas de escolha.
  """
  use Ash.Resource,
    otp_app: :h_stock,
    domain: Core.Inventory,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  sqlite do
    table "stock_batches"
    repo Core.Repo

    references do
      reference :product, on_delete: :delete
    end

    custom_indexes do
      index [:product_id, :depleted_at]
    end
  end

  actions do
    defaults [:read]

    read :for_product do
      argument :product_id, :uuid, allow_nil?: false

      filter expr(product_id == ^arg(:product_id))
      prepare build(sort: [depleted_at: :asc_nils_first, inserted_at: :asc], load: [:user])
    end

    read :available do
      description "Lotes com saldo — os únicos de onde dá para tirar mercadoria."

      filter expr(remaining_grams > 0)
      prepare build(sort: [inserted_at: :asc])
    end

    create :create do
      primary? true

      accept [
        :label,
        :cost_per_gram,
        :initial_grams,
        :remaining_grams,
        :product_id,
        :user_id
      ]
    end

    update :update do
      primary? true
      accept [:remaining_grams, :depleted_at]
    end

    update :correct_cost do
      description """
      Corrige o custo pago por este lote — o número digitado errado na compra.
      Não move estoque: acerta o que a venda usa para calcular lucro daqui
      para a frente. O que já saiu daqui guarda o custo que tinha na hora.
      """

      require_atomic? false
      accept [:cost_per_gram]

      argument :reason, :string

      change Core.Inventory.Changes.CorrectBatchCost
    end
  end

  policies do
    # O funcionário precisa enxergar os lotes para escolher de qual vende. O
    # custo não vaza por isso: quem esconde o campo de quem não gerencia
    # estoque é o `Web.Serializers`.
    policy action_type(:read) do
      authorize_if actor_present()
    end

    # Corrigir custo é a única escrita que se pede ao lote diretamente, e é do
    # grupo do estoque — a mesma régua de quem enxerga custo nas telas.
    policy action(:correct_cost) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:can_manage_stock, true)
    end

    # O resto: lote nasce e muda por dentro das ações de estoque do produto,
    # que rodam com `authorize?: false` depois de já terem validado a
    # permissão.
    policy action([:create, :update]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :label, :string do
      description "Como o balcão chama esse lote: \"Laranja da feira\", \"Caixa 12/08\"."
      allow_nil? false
      public? true
      constraints min_length: 2, trim?: true
    end

    attribute :cost_per_gram, :decimal do
      description "Quanto custou a grama desta compra. Base do lucro da venda."
      allow_nil? false
      public? true
      constraints min: 0
    end

    attribute :initial_grams, :decimal do
      description "O que entrou. Não muda — serve de referência do consumo."
      allow_nil? false
      public? true
      constraints greater_than: 0
    end

    attribute :remaining_grams, :decimal do
      description "O que ainda há deste lote."
      allow_nil? false
      public? true
      constraints min: 0
    end

    attribute :depleted_at, :utc_datetime_usec do
      description "Quando o lote zerou. Preenchido some das listas de escolha."
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :product, Core.Inventory.Product do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :user, Core.Accounts.User do
      description "Quem deu entrada no lote."
      attribute_writable? true
    end

    has_many :movements, Core.Inventory.StockMovement do
      sort inserted_at: :desc
    end
  end

  calculations do
    calculate :cost_per_kg,
              :decimal,
              {Core.Calculations.Arithmetic, mult: [:cost_per_gram, 1000]} do
      public? true
    end

    calculate :remaining_cost,
              :decimal,
              {Core.Calculations.Arithmetic, mult: [:remaining_grams, :cost_per_gram]} do
      description "Quanto dinheiro ainda está parado neste lote."
      public? true
    end

    calculate :depleted?, :boolean, expr(remaining_grams <= 0) do
      public? true
    end
  end

  @doc """
  Nome do lote quando quem deu entrada não informou nenhum.

  "Lote de 12/08" é o que a pessoa diria em voz alta — melhor do que um id ou
  um campo vazio na lista de escolha da venda.
  """
  @spec label_or_default(String.t() | nil) :: String.t()
  def label_or_default(label) when is_binary(label) do
    case String.trim(label) do
      "" -> default_label()
      informed -> informed
    end
  end

  def label_or_default(_label), do: default_label()

  defp default_label do
    date = Core.Clock.today()
    "Lote de #{pad(date.day)}/#{pad(date.month)}"
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
