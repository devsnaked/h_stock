defmodule Core.Inventory do
  @moduledoc """
  Estoque: produtos vendidos a peso, os lotes que os abastecem e o histórico
  de movimentações.

  Tudo é guardado em **gramas** (`Decimal`). A unidade do produto (`:g` ou
  `:kg`) diz apenas como ele é digitado e exibido; preço e custo são sempre
  por grama.

  O estoque é organizado em **lotes** (`Core.Inventory.Batch`) e lotes não se
  misturam: cada compra entra com o seu custo e mantém o seu saldo. Entrada
  abre lote; saída, devolução e ajuste dizem em qual lote estão mexendo. O
  saldo do produto (`stock_grams`) é a soma dos lotes e só muda por essas
  ações, que gravam a movimentação correspondente na mesma transação.

  É o custo do lote que permite calcular lucro: a venda copia o custo do lote
  escolhido para o item do pedido.
  """
  use Ash.Domain, otp_app: :h_stock

  resources do
    resource Core.Inventory.Product do
      define :list_products, action: :read
      define :list_active_products, action: :active
      define :get_product, action: :read, get_by: [:id]
      define :create_product, action: :create
      define :update_product, action: :update
      define :add_stock, action: :add_stock, args: [:grams, :cost_per_gram]
      define :remove_stock, action: :remove_stock, args: [:grams, :batch_id]
      define :return_stock, action: :return_stock, args: [:grams, :batch_id]
      define :adjust_stock, action: :adjust_stock, args: [:grams, :batch_id]
    end

    resource Core.Inventory.Batch do
      define :list_batches, action: :read
      define :get_batch, action: :read, get_by: [:id]
      define :list_batches_for_product, action: :for_product, args: [:product_id]
      define :list_available_batches, action: :available
      define :correct_batch_cost, action: :correct_cost, args: [:cost_per_gram]
    end

    resource Core.Inventory.StockMovement do
      define :list_movements, action: :read
      define :list_movements_for_product, action: :for_product, args: [:product_id]
    end
  end
end
