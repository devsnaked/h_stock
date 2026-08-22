# Dados iniciais.
#
#     mix ecto.setup    # já roda este arquivo
#     mix run priv/repo/seeds.exs
#
# É idempotente: rodar de novo não duplica nada, e não mexe em quem já existe
# (rodar depois de trocar a senha do admin não a reverte).
#
# O admin é o único registro indispensável — sem ele não há como entrar no
# sistema para cadastrar mais ninguém, já que não existe cadastro público.
# Produtos e funcionário de exemplo saem com `SEED_DEMO=false`.

require Ash.Query

alias Core.Accounts.User
alias Core.Inventory
alias Core.Inventory.Product

admin_nickname = System.get_env("ADMIN_NICKNAME", "admin")
admin_password = System.get_env("ADMIN_PASSWORD", "Pass@123!")
demo? = System.get_env("SEED_DEMO", "true") == "true"

find_user = fn nickname ->
  User
  |> Ash.Query.filter(nickname == ^nickname)
  |> Ash.read_one!(authorize?: false)
end

find_product = fn name ->
  Product
  |> Ash.Query.filter(name == ^name)
  |> Ash.read_one!(authorize?: false)
end

admin =
  find_user.(admin_nickname) ||
    User.create_user!(
      admin_nickname,
      "Administrador",
      admin_password,
      admin_password,
      %{role: :admin},
      authorize?: false
    )

if demo? do
  # O funcionário do demo nasce com o painel inteiro para que a home dele possa
  # ser percorrida; num sistema de verdade cada seção é liberação do admin, na
  # tela de Equipe. Estoque e pedidos da equipe continuam fechados para ele — é
  # o funcionário comum.
  find_user.("funcionario") ||
    User.create_user!(
      "funcionario",
      "Funcionário",
      admin_password,
      admin_password,
      %{
        role: :employee,
        can_view_dashboard: true,
        dashboard_sections: Core.Accounts.Permissions.dashboard_sections()
      },
      authorize?: false
    )

  # O entregador existe no demo para o fluxo da entrega poder ser percorrido
  # inteiro: registrar o pedido, mandar para ele, e marcar a chegada.
  find_user.("entregador") ||
    User.create_user!(
      "entregador",
      "Entregador",
      admin_password,
      admin_password,
      %{role: :driver},
      authorize?: false
    )

  # `custo` é por grama, como o preço. `segundo_lote` existe para o demo já
  # nascer com o caso que importa: o mesmo produto comprado por dois preços.
  produtos = [
    %{
      name: "Café em grão",
      unit: :kg,
      price: "0.062",
      custo: "0.038",
      min: 2_000,
      inicial: 15_000,
      lote: "Safra da fazenda",
      segundo_lote: %{grams: 8_000, custo: "0.045", label: "Compra de emergência"}
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

  for produto <- produtos do
    product =
      find_product.(produto.name) ||
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

    with %{grams: grams, custo: custo, label: label} <- Map.get(produto, :segundo_lote),
         [_only_one] <- Inventory.list_batches_for_product!(product.id, authorize?: false) do
      Inventory.add_stock!(
        product,
        Decimal.new(grams),
        Decimal.new(custo),
        %{label: label, reason: "Reposição"},
        actor: admin,
        authorize?: false
      )
    end
  end
end

IO.puts("""

Seeds aplicados.

  #{admin_nickname}   senha: #{admin_password}   (admin)#{if demo?, do: "\n  funcionario   senha: #{admin_password}   (funcionário)", else: ""}

Troque a senha em /usuarios assim que entrar.
""")
