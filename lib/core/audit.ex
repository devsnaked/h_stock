defmodule Core.Audit do
  @moduledoc """
  Log de auditoria: quem mexeu no estoque e nos pedidos, e o que fez.

  Existe porque as duas perguntas do administrador — "quem baixou esse
  estoque?" e "quem cancelou esse pedido?" — não tinham uma resposta só. O
  `Core.Inventory.StockMovement` responde a primeira muito bem, mas é um
  **livro-razão**: ele existe para o saldo bater, e por isso só enxerga o que
  mexe em gramas. Alteração de preço, cadastro de produto, cancelamento de
  venda e despacho de entrega não passam por ele.

  Então o log é uma tabela à parte, e **completa por construção**: a tela do
  administrador lê só daqui. Juntar duas fontes faria a completude depender de
  alguém lembrar de consultar as duas — e o dia em que uma ação nova esquecer
  de aparecer é justamente o dia em que ninguém percebe.

  ## Escrever no log

  `record/4` é chamado de dentro das changes que já fazem o trabalho, na mesma
  transação (ver `Core.Changes.InTransaction`). Se a gravação do log falhar, a
  ação inteira falha junto — de propósito: mudança de estoque que não foi
  registrada é exatamente o que este módulo existe para tornar impossível.

  ## Ler

  Só o administrador, e é a policy de `Core.Audit.Entry` que garante isso —
  o plug da rota apenas evita que os outros vejam uma tela de erro.
  """
  use Ash.Domain, otp_app: :h_stock

  resources do
    resource Core.Audit.Entry do
      define :feed, action: :feed
    end
  end

  alias Core.Audit.Entry
  alias Core.Inventory.Product
  alias Core.Orders
  alias Core.Orders.Order

  @doc """
  Grava uma linha do log.

  `subject` é o produto ou o pedido a que o fato se refere — dele saem o tipo
  e o rótulo congelado. `actor` é quem agiu; `nil` só em seed ou script de
  manutenção.

  Levanta em vez de devolver `{:error, _}`: o retorno ignorado seria um log
  com buracos silenciosos, e quem chama está sempre dentro de uma transação
  que sabe desfazer o resto.
  """
  @spec record(atom(), Product.t() | Order.t(), map() | nil, keyword()) :: Entry.t()
  def record(action, subject, actor, opts \\ []) do
    {subject_type, subject_label} = subject(subject)

    Entry
    |> Ash.Changeset.for_create(
      :record,
      %{
        action: action,
        subject_type: subject_type,
        subject_id: subject.id,
        subject_label: subject_label,
        summary: Keyword.fetch!(opts, :summary),
        details: Keyword.get(opts, :details, %{}),
        user_id: actor && actor.id,
        user_name: actor && actor.name
      },
      authorize?: false
    )
    |> Ash.create!()
  end

  defp subject(%Product{} = product), do: {:product, product.name}
  defp subject(%Order{} = order), do: {:order, Orders.code(order)}

  @doc """
  Peso como a loja fala dele: `250g`, `1.5kg`.

  Acima de mil gramas a leitura em quilos é a que a pessoa confere de cabeça —
  "saíram 2.4kg" diz mais que "saíram 2400g". Zeros à direita somem: o lote é
  de `500g`, não de `500.000g`.
  """
  @spec grams(Decimal.t()) :: String.t()
  def grams(%Decimal{} = value) do
    abs = Decimal.abs(value)

    if Decimal.compare(abs, 1000) == :lt do
      "#{trim(abs)}g"
    else
      "#{trim(Decimal.div(abs, 1000))}kg"
    end
  end

  @doc "Dinheiro em real, com vírgula: `R$ 8,50`."
  @spec money(Decimal.t()) :: String.t()
  def money(%Decimal{} = value) do
    "R$ " <> String.replace(Decimal.to_string(Decimal.round(value, 2), :normal), ".", ",")
  end

  defp trim(%Decimal{} = value) do
    value
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
