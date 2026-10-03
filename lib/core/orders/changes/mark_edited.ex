defmodule Core.Orders.Changes.MarkEdited do
  @moduledoc """
  Grava no próprio pedido quem fez a última edição, e quando.

  É o "editado por Joana às 15h" que o administrador vê na tela do pedido; o
  histórico inteiro, com o que havia antes de cada edição, fica no log de
  auditoria (`Core.Orders.Changes.LogOrderEvent`).

  Só marca quando algo de fato muda: salvar o formulário sem mexer em nada
  não pode fazer o pedido parecer alterado. O Ash já tira do changeset o
  campo que voltou com o mesmo valor, então "mudou" é "está no changeset" —
  ou, nos itens, o plano que `Core.Orders.Changes.EditItems` deixou no
  contexto. Por isso roda como `before_action`, depois do dela.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if edited?(changeset) do
        changeset
        |> Ash.Changeset.force_change_attribute(:edited_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:edited_by_id, context.actor && context.actor.id)
      else
        changeset
      end
    end)
  end

  defp edited?(changeset) do
    changeset.context[:item_plan] != nil or
      Enum.any?(changeset.action.accept, &Ash.Changeset.changing_attribute?(changeset, &1))
  end
end
