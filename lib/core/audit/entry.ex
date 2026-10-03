defmodule Core.Audit.Entry do
  @moduledoc """
  Uma linha do log: quem fez, o quê, quando, e sobre qual produto ou pedido.

  É **append-only**. Não há ação de update nem de destroy — nem para o admin.
  Um registro que pode ser corrigido depois não serve para conferir nada.

  Tudo o que a linha precisa para ser lida daqui a um ano está **congelado
  nela**: o nome de quem agiu (`user_name`), o nome do produto ou o código do
  pedido (`subject_label`) e a frase pronta (`summary`). Produto renomeado,
  preço alterado, usuário desativado — nada disso reescreve o passado. É a
  mesma escolha do `Core.Orders.OrderItem`, pelo mesmo motivo.

  `user_id` e `subject_id` ficam ao lado dos rótulos congelados para filtrar
  e para abrir o registro atual; quem manda no texto é o rótulo.

  `details` guarda os números crus (gramas, preço antes/depois) para quem
  precisar conferir a conta — a frase é para ler, o mapa é para auditar.
  """
  use Ash.Resource,
    otp_app: :h_stock,
    domain: Core.Audit,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  sqlite do
    table "audit_entries"
    repo Core.Repo

    references do
      reference :user, on_delete: :nilify
    end

    custom_indexes do
      # A tela sempre lê em ordem cronológica inversa, quase sempre recortada
      # por período.
      index [:inserted_at]
      index [:subject_type, :inserted_at]
    end
  end

  actions do
    defaults [:read]

    read :feed do
      description """
      O log inteiro, do mais novo para o mais antigo.

      Paginado porque o log só cresce: uma loja em operação passa de mil
      linhas em semanas, e a tela mostra trinta por vez. `required? false`
      pela mesma razão dos pedidos — quem exportar o período inteiro continua
      lendo sem pedir página.
      """

      prepare build(sort: [inserted_at: :desc])

      pagination offset?: true, default_limit: 30, countable: true, required?: false
    end

    create :record do
      description "Grava uma linha. Só o domínio chama, sempre com `authorize?: false`."
      primary? true

      accept [
        :action,
        :subject_type,
        :subject_id,
        :subject_label,
        :summary,
        :details,
        :user_id,
        :user_name
      ]
    end
  end

  policies do
    # O log é do administrador e de mais ninguém. O plug `RequireAdmin` manda
    # os outros de volta com um aviso; esta policy é o que realmente fecha a
    # porta, inclusive para quem chegar por outro caminho que não a tela.
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    # Escrita nasce por dentro das ações de estoque e de pedido, que já
    # validaram a permissão e chamam com `authorize?: false`. Ninguém escreve
    # no log a partir de uma requisição.
    policy action_type(:create) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    @doc "O que aconteceu. A lista é fechada: ação nova entra aqui e na tela."
    attribute :action, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :product_created,
                    :product_updated,
                    :stock_in,
                    :stock_out,
                    :stock_return,
                    :stock_adjusted,
                    :stock_cost_corrected,
                    :order_registered,
                    :order_cancelled,
                    :order_driver_assigned,
                    :order_out_for_delivery,
                    :order_delivered,
                    :order_reopened,
                    :order_paid,
                    :order_updated
                  ]
    end

    attribute :subject_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:product, :order]
    end

    attribute :subject_id, :uuid do
      description "Sem chave estrangeira: o log sobrevive ao que ele descreve."
      allow_nil? false
      public? true
    end

    attribute :subject_label, :string do
      description "Nome do produto ou código do pedido, como estavam na hora."
      allow_nil? false
      public? true
    end

    attribute :summary, :string do
      description "A frase que a tela mostra, escrita na hora do fato."
      allow_nil? false
      public? true
    end

    attribute :details, :map do
      description "Números crus do fato: gramas, custo, preço antes e depois."
      public? true
      default %{}
    end

    attribute :user_name, :string do
      description """
      Quem fez, congelado. Fica nulo só quando não havia ator — hoje isso não
      acontece por nenhum caminho da aplicação, mas um seed ou um script de
      manutenção rodam sem usuário, e o log precisa aceitar dizer "não sei".
      """

      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :user, Core.Accounts.User do
      description "Para filtrar por pessoa e abrir o cadastro atual dela."
      allow_nil? true
      public? true
    end
  end
end
