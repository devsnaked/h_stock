defmodule Core.Orders.Changes.AssignDriver do
  @moduledoc """
  Põe o pedido na mão de um entregador.

  Serve às duas portas de entrada: o despacho de um pedido que já existe
  (`:assign_driver`) e a venda que já sai com entregador definido
  (`:register`, onde o argumento é opcional — vazio quer dizer "decide
  depois", e é o caso comum de quem ainda vai embalar).

  A checagem de que o destinatário é mesmo um entregador ativo mora aqui, e
  não no formulário: quem despacha enxerga a própria conta na leitura de
  usuários, então sem esta validação daria para mandar o pedido para si
  mesmo — ou para um entregador desligado, que não vai abrir o app de novo.

  A busca vai com `authorize?: false` de propósito: a policy da ação já disse
  que este ator pode despachar este pedido, e o que falta aqui é uma regra de
  domínio, não de acesso.
  """
  use Ash.Resource.Change

  alias Core.Accounts.User

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :driver_id) do
      nil -> changeset
      driver_id -> assign(changeset, driver_id)
    end
  end

  defp assign(changeset, driver_id) do
    cond do
      # Retirada no balcão não tem para onde mandar: quem desligou a entrega e
      # escolheu entregador está se contradizendo, e o formulário precisa
      # saber disso em vez de gravar um entregador que ninguém verá.
      Ash.Changeset.get_attribute(changeset, :delivery_status) == :not_required ->
        Ash.Changeset.add_error(changeset,
          field: :driver_id,
          message: "pedido de retirada no balcão não vai para entregador"
        )

      true ->
        case Ash.get(User, driver_id, authorize?: false) do
          {:ok, %{role: :driver, active: true}} ->
            changeset
            |> Ash.Changeset.force_change_attribute(:driver_id, driver_id)
            |> Ash.Changeset.force_change_attribute(:assigned_at, DateTime.utc_now())

          {:ok, %{role: :driver}} ->
            Ash.Changeset.add_error(changeset,
              field: :driver_id,
              message: "este entregador está desativado"
            )

          _other ->
            Ash.Changeset.add_error(changeset,
              field: :driver_id,
              message: "escolha um entregador"
            )
        end
    end
  end
end
