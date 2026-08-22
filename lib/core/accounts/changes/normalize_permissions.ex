defmodule Core.Accounts.Changes.NormalizePermissions do
  @moduledoc """
  Permissão incoerente não chega ao banco.

  Duas coisas são arrumadas aqui, e não na tela — assim um perfil trocado pelo
  formulário, ou um `set_permissions` chamado de qualquer outro lugar, não
  deixa uma permissão de pé onde ela não deveria estar:

    * **entregador não gerencia e não analisa nada.** As permissões
      (`can_manage_stock`, `can_manage_orders`, `can_view_dashboard`,
      `dashboard_sections`) só descrevem quem trabalha no balcão; quem vira
      entregador perde todas.

    * **seção de painel sem painel não existe.** Sem `can_view_dashboard` a
      lista de seções é esvaziada: permissão pendurada é a que volta a valer
      sozinha no dia em que alguém religa a chave, sem ninguém ter escolhido
      isso. O que sobra é reordenado pela ordem canônica de
      `Core.Accounts.Permissions.dashboard_sections/0` e perde repetições — a
      lista guardada lê como a tela.
  """
  use Ash.Resource.Change

  alias Core.Accounts.Permissions

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :role) do
      :driver -> clear(changeset)
      _role -> normalize_dashboard(changeset)
    end
  end

  defp clear(changeset) do
    changeset
    |> Ash.Changeset.force_change_attribute(:can_manage_stock, false)
    |> Ash.Changeset.force_change_attribute(:can_manage_orders, false)
    |> Ash.Changeset.force_change_attribute(:can_view_dashboard, false)
    |> Ash.Changeset.force_change_attribute(:dashboard_sections, [])
  end

  defp normalize_dashboard(changeset) do
    if Ash.Changeset.get_attribute(changeset, :can_view_dashboard) do
      sections = Ash.Changeset.get_attribute(changeset, :dashboard_sections) || []

      Ash.Changeset.force_change_attribute(
        changeset,
        :dashboard_sections,
        Enum.filter(Permissions.dashboard_sections(), &(&1 in sections))
      )
    else
      Ash.Changeset.force_change_attribute(changeset, :dashboard_sections, [])
    end
  end
end
