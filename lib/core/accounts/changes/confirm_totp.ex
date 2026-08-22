defmodule Core.Accounts.Changes.ConfirmTotp do
  @moduledoc """
  Fecha a ativação da verificação em duas etapas.

  Só liga de fato se o primeiro código bater — assim ninguém termina com o
  2FA ativo e um aplicativo que, por qualquer motivo, gera outro número.
  Junto vêm os códigos de recuperação: os hashes ficam guardados, e os
  códigos em claro voltam no metadata para a tela mostrá-los uma única vez.
  """
  use Ash.Resource.Change

  alias Core.Accounts.Totp

  @impl true
  def change(changeset, _opts, _context) do
    code = Ash.Changeset.get_argument(changeset, :code)
    secret = changeset.data.totp_secret

    cond do
      is_nil(secret) ->
        Ash.Changeset.add_error(changeset,
          field: :code,
          message: "comece a ativação de novo — não há um segredo pendente"
        )

      not Totp.valid?(secret, code, nil) ->
        Ash.Changeset.add_error(changeset,
          field: :code,
          message: "código incorreto. Confira o relógio do celular e tente o próximo"
        )

      true ->
        {codes, hashes} = Totp.generate_recovery_codes()

        changeset
        |> Ash.Changeset.force_change_attribute(:totp_confirmed_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:totp_last_used_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:totp_recovery_hashes, hashes)
        |> Ash.Changeset.after_action(fn _changeset, user ->
          {:ok, Ash.Resource.put_metadata(user, :recovery_codes, codes)}
        end)
    end
  end
end
