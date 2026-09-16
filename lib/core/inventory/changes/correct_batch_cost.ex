defmodule Core.Inventory.Changes.CorrectBatchCost do
  @moduledoc """
  Registra no log de auditoria a correção do custo de um lote.

  Corrigir custo **não é movimentar estoque**: nada entra, nada sai, e por isso
  não há linha no histórico de movimentações — o que muda é quanto se pagou
  pelo que já está lá. Mas é dinheiro, e decide o lucro de tudo que ainda vai
  sair deste lote; o log guarda de quanto para quanto, quem mudou e por quê.

  **A correção vale daqui para a frente.** As vendas que já saíram deste lote
  copiaram o custo delas para o item do pedido — é o que impede o lucro de um
  pedido fechado de se reescrever sozinho — e continuam com o custo antigo.
  """
  use Ash.Resource.Change

  alias Core.Inventory.Product

  @impl true
  def change(changeset, _opts, context) do
    anterior = changeset.data.cost_per_gram

    Ash.Changeset.after_action(changeset, fn changeset, batch ->
      audit(batch, anterior, Ash.Changeset.get_argument(changeset, :reason), context)
      {:ok, batch}
    end)
  end

  defp audit(batch, anterior, reason, context) do
    # O log é do produto, como o resto do estoque: quem confere procura pelo
    # que vende, não pelo id do lote.
    product = Ash.get!(Product, batch.product_id, authorize?: false)

    Core.Audit.record(:stock_cost_corrected, product, context.actor,
      summary: summary(batch, anterior, reason),
      details: %{
        batch_label: batch.label,
        cost_per_gram_before: to_string(anterior),
        cost_per_gram: to_string(batch.cost_per_gram),
        remaining_grams: to_string(batch.remaining_grams),
        reason: reason
      }
    )
  end

  defp summary(batch, anterior, reason) do
    [
      "Custo do lote #{batch.label} corrigido de #{Core.Audit.money(anterior)}/g " <>
        "para #{Core.Audit.money(batch.cost_per_gram)}/g",
      reason,
      "há #{Core.Audit.grams(batch.remaining_grams)} neste lote"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" — ")
  end
end
