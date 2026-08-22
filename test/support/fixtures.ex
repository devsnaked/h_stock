defmodule Core.Fixtures do
  @moduledoc """
  Fixtures dos testes.

  Tudo é criado com `authorize?: false`: quem está sendo testado é a regra de
  negócio da ação sob teste, não a permissão de montar o cenário.
  """

  alias Core.Accounts.User
  alias Core.Inventory

  @password "senha-de-teste"

  def password, do: @password

  @permissions [
    :role,
    :can_manage_stock,
    :can_manage_orders,
    :can_view_dashboard,
    :dashboard_sections
  ]

  @doc """
  Usuário de teste. Nasce sem permissão nenhuma além do perfil, como no
  sistema: `can_manage_stock`, `can_manage_orders` e `can_view_dashboard` são
  liberações do admin, e o teste que depende de uma delas pede explicitamente.

  `dashboard_sections: :all` é o atalho para "o painel inteiro" — a lista de
  seções vive em `Core.Accounts.Permissions`, e repeti-la em cada teste só
  criaria uma segunda lista para esquecer de atualizar.
  """
  def user_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        role: :employee,
        can_manage_stock: false,
        can_manage_orders: false,
        can_view_dashboard: false,
        dashboard_sections: []
      })

    attrs = Map.update!(attrs, :dashboard_sections, &sections/1)
    suffix = System.unique_integer([:positive])

    user =
      User.create_user!(
        Map.get(attrs, :nickname, "user#{suffix}"),
        Map.get(attrs, :name, "Usuário #{suffix}"),
        @password,
        @password,
        Map.take(attrs, @permissions),
        authorize?: false
      )

    # O 2FA é obrigatório para usar o sistema, então o usuário de teste já
    # nasce com ele ativo — do contrário todo teste esbarraria na tela de
    # ativação. Passe `two_factor: false` para testar justamente esse caso.
    if Map.get(attrs, :two_factor, true), do: enroll_totp(user), else: user
  end

  defp sections(:all), do: Core.Accounts.Permissions.dashboard_sections()
  defp sections(list) when is_list(list), do: list

  @doc """
  Ativa o 2FA de um usuário como se ele tivesse escaneado o QR Code.

  O `totp_last_used_at` volta a `nil` porque a confirmação gasta o código
  daquela janela de 30s — e nos testes tudo acontece no mesmo segundo.
  """
  def enroll_totp(user) do
    {:ok, user} = User.start_totp_enrollment(user, actor: user)
    code = NimbleTOTP.verification_code(user.totp_secret)
    {:ok, confirmed} = User.confirm_totp(user, code, actor: user)

    import Ecto.Query

    Core.Repo.update_all(
      from(u in "users", where: u.id == type(^user.id, :binary_id)),
      set: [totp_last_used_at: nil]
    )

    # Os códigos de recuperação seguem no metadata: recarregar do banco os
    # perderia, e é a única vez que existem em claro.
    User
    |> Ash.get!(user.id, authorize?: false)
    |> Ash.Resource.put_metadata(:recovery_codes, confirmed.__metadata__.recovery_codes)
  end

  def admin_fixture(attrs \\ %{}), do: user_fixture(Map.put(Map.new(attrs), :role, :admin))

  @doc "Entregador: o perfil que só recebe pedidos prontos e marca a entrega."
  def driver_fixture(attrs \\ %{}), do: user_fixture(Map.put(Map.new(attrs), :role, :driver))

  @doc """
  Produto já com o primeiro lote. `cost_per_gram` tem custo de verdade (não
  zero) para que qualquer venda no teste renda um lucro conferível.
  """
  def product_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    suffix = System.unique_integer([:positive])

    Inventory.create_product!(
      %{
        name: Map.get(attrs, :name, "Produto #{suffix}"),
        unit: Map.get(attrs, :unit, :kg),
        price_per_gram: decimal(Map.get(attrs, :price_per_gram, "0.05")),
        min_stock_grams: decimal(Map.get(attrs, :min_stock_grams, 0)),
        initial_stock_grams: decimal(Map.get(attrs, :stock_grams, 1_000)),
        initial_cost_per_gram: decimal(Map.get(attrs, :cost_per_gram, "0.02")),
        initial_batch_label: Map.get(attrs, :batch_label, "Lote inicial")
      },
      authorize?: false
    )
  end

  @doc "Entrada de mercadoria: abre mais um lote no produto e o devolve."
  def batch_fixture(product, attrs \\ %{}) do
    attrs = Map.new(attrs)

    {:ok, _product} =
      Inventory.add_stock(
        product,
        decimal(Map.get(attrs, :grams, 1_000)),
        decimal(Map.get(attrs, :cost_per_gram, "0.03")),
        %{label: Map.get(attrs, :label), reason: Map.get(attrs, :reason)},
        authorize?: false
      )

    product |> batches() |> List.last()
  end

  @doc "Lotes do produto, do mais antigo para o mais novo."
  def batches(product) do
    Inventory.list_batches_for_product!(product.id, authorize?: false)
  end

  @doc "O primeiro lote do produto — o que a maioria dos testes vende."
  def batch_of(product), do: product |> batches() |> hd()

  @doc """
  Item de pedido pronto para `register_order`. Sem lote informado usa o
  primeiro do produto, que é de onde a venda sairia no balcão.
  """
  def sale_item(product, grams, batch \\ nil) do
    batch = batch || batch_of(product)

    %{product_id: product.id, batch_id: batch.id, grams: decimal(grams)}
  end

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value) when is_binary(value), do: Decimal.new(value)
  defp decimal(value) when is_integer(value), do: Decimal.new(value)
end
