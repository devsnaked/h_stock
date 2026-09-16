defmodule Core.Demo do
  @moduledoc """
  A loja de mentira: a equipe e o catálogo de exemplo.

  Existe porque tela vazia não se avalia — um painel sem venda, um catálogo
  sem produto e uma fila de entrega sem entregador não mostram se o sistema
  está certo. Isto aqui é o cenário mínimo para percorrer o produto inteiro.

  **Só em desenvolvimento.** Quem chama são os seeds (que só o fazem quando
  `Mix.env() == :dev`) e o `mix demo.orders`, que se recusa a rodar em
  produção. Em produção o seed cria o administrador e mais nada — o resto
  nasce das telas, pelas mãos dele.

  É idempotente: cada pessoa e cada produto só são criados se ainda não
  existirem, então rodar de novo não duplica nem reverte o que foi mexido.
  """

  require Ash.Query

  alias Core.Accounts.Permissions
  alias Core.Accounts.User
  alias Core.Inventory
  alias Core.Inventory.Product

  @password "Pass@123!"

  # `custo` é por grama, como o preço. Cada produto nasce com um lote; o
  # segundo lote — o caso que importa, o mesmo produto comprado por dois
  # preços — vem da carga do `mix demo.orders`.
  @products [
    %{
      name: "Café em grão",
      unit: :kg,
      price: "0.062",
      custo: "0.038",
      min: 2_000,
      inicial: 15_000,
      lote: "Safra da fazenda"
    },
    %{
      name: "Castanha de caju",
      unit: :kg,
      price: "0.089",
      custo: "0.061",
      min: 1_000,
      inicial: 6_500,
      lote: "Caixa do fornecedor"
    },
    %{
      name: "Açafrão",
      unit: :g,
      price: "0.850",
      custo: "0.520",
      min: 100,
      inicial: 480,
      lote: "Pote de 500g"
    }
  ]

  @doc "A senha de todo mundo do exemplo. É de mentira; não vá para produção."
  @spec password() :: String.t()
  def password, do: @password

  @doc """
  Cria o que faltar do cenário: funcionário, entregador e os três produtos.

  Precisa de um administrador — é ele que consta como autor da entrada de
  mercadoria, e é ele quem existiria numa loja de verdade antes de qualquer
  outra coisa.
  """
  @spec ensure_cast(User.t()) :: :ok
  def ensure_cast(admin) do
    # O funcionário do exemplo nasce com o painel inteiro para que a home dele
    # possa ser percorrida; num sistema de verdade cada seção é liberação do
    # admin, na tela de Equipe.
    ensure_user("funcionario", "Funcionário", %{
      role: :employee,
      can_view_dashboard: true,
      dashboard_sections: Permissions.dashboard_sections()
    })

    ensure_user("entregador", "Entregador", %{role: :driver})

    ensure_products(admin)

    :ok
  end

  @doc "O administrador que já existe, ou `nil` se ainda não houver nenhum."
  @spec admin() :: User.t() | nil
  def admin do
    User
    |> Ash.read!(authorize?: false)
    |> Enum.find(&(&1.role == :admin))
  end

  defp ensure_user(nickname, name, attrs) do
    find_user(nickname) ||
      User.create_user!(nickname, name, @password, @password, attrs, authorize?: false)
  end

  defp find_user(nickname) do
    User
    |> Ash.Query.filter(nickname == ^nickname)
    |> Ash.read_one!(authorize?: false)
  end

  defp ensure_products(admin) do
    for produto <- @products, find_product(produto.name) == nil do
      Inventory.create_product!(
        %{
          name: produto.name,
          unit: produto.unit,
          price_per_gram: Decimal.new(produto.price),
          min_stock_grams: Decimal.new(produto.min),
          initial_stock_grams: Decimal.new(produto.inicial),
          initial_cost_per_gram: Decimal.new(produto.custo),
          initial_batch_label: produto.lote
        },
        actor: admin,
        authorize?: false
      )
    end
  end

  defp find_product(name) do
    Product
    |> Ash.Query.filter(name == ^name)
    |> Ash.read_one!(authorize?: false)
  end
end
