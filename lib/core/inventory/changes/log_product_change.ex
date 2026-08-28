defmodule Core.Inventory.Changes.LogProductChange do
  @moduledoc """
  Registra no log de auditoria o cadastro e a alteração de um produto.

  O `Core.Inventory.StockMovement` não cobre isto: ele só enxerga o que mexe
  em gramas. Mas mudar o preço de um produto é uma decisão de dinheiro tão
  auditável quanto uma saída de mercadoria — e desativar um produto o tira do
  balcão sem alterar saldo nenhum. Sem esta change, as duas coisas
  aconteceriam sem deixar rastro de quem fez.

  Na alteração, só o que **de fato mudou** vira linha: salvar o formulário sem
  tocar em nada não polui o log. Preço aparece por quilo, que é como a loja
  fala dele e como as telas o mostram — o campo guardado continua por grama.
  """
  use Ash.Resource.Change

  # A ordem aqui é a ordem em que os campos aparecem na frase.
  @tracked [
    {:name, "Nome"},
    {:price_per_gram, "Preço"},
    {:min_stock_grams, "Estoque mínimo"},
    {:unit, "Unidade"},
    {:active, "Situação"}
  ]

  @impl true
  def change(changeset, opts, context) do
    case Keyword.fetch!(opts, :action) do
      :created -> log_creation(changeset, context)
      :updated -> log_update(changeset, context)
    end
  end

  defp log_creation(changeset, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, product ->
      Core.Audit.record(:product_created, product, context.actor,
        summary: "Produto cadastrado a #{per_kg(product.price_per_gram)}",
        details: %{
          price_per_gram: to_string(product.price_per_gram),
          min_stock_grams: to_string(product.min_stock_grams),
          unit: to_string(product.unit)
        }
      )

      {:ok, product}
    end)
  end

  defp log_update(changeset, context) do
    Ash.Changeset.after_action(changeset, fn changeset, product ->
      case diff(changeset.data, product) do
        [] ->
          {:ok, product}

        changes ->
          Core.Audit.record(:product_updated, product, context.actor,
            summary: changes |> Enum.map(& &1.sentence) |> Enum.join("; "),
            details: Map.new(changes, &{&1.field, %{de: &1.from, para: &1.to}})
          )

          {:ok, product}
      end
    end)
  end

  defp diff(before, now) do
    Enum.flat_map(@tracked, fn {field, label} ->
      old = Map.fetch!(before, field)
      new = Map.fetch!(now, field)

      if same?(old, new) do
        []
      else
        [
          %{
            field: to_string(field),
            from: to_string(old),
            to: to_string(new),
            sentence: sentence(field, label, old, new)
          }
        ]
      end
    end)
  end

  # `Decimal` não compara bem com `==`: "9.00" e "9.0" são o mesmo preço, e
  # uma alteração que não alterou nada não deve virar linha no log.
  defp same?(%Decimal{} = old, %Decimal{} = new), do: Decimal.equal?(old, new)
  defp same?(old, new), do: old == new

  defp sentence(:active, _label, _old, true), do: "Produto reativado"
  defp sentence(:active, _label, _old, false), do: "Produto desativado"

  defp sentence(:price_per_gram, label, old, new),
    do: "#{label} alterado de #{per_kg(old)} para #{per_kg(new)}"

  defp sentence(:min_stock_grams, label, old, new),
    do: "#{label} alterado de #{Core.Audit.grams(old)} para #{Core.Audit.grams(new)}"

  defp sentence(_field, label, old, new),
    do: "#{label} alterado de #{old} para #{new}"

  defp per_kg(price_per_gram),
    do: "#{Core.Audit.money(Decimal.mult(price_per_gram, 1000))}/kg"
end
