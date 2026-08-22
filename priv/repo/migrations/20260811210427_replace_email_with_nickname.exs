defmodule Core.Repo.Migrations.ReplaceEmailWithNickname do
  @moduledoc """
  Login passa a ser por `nickname`; o e-mail deixa de existir.

  `nickname` entra como `NOT NULL` sem valor padrão, então esta migração
  **exige a tabela de usuários vazia** — é o combinado: o banco de
  desenvolvimento é recriado (`mix ecto.reset`) em vez de convertermos
  e-mails em apelidos. Numa base com gente cadastrada, o caminho seria
  preencher `nickname` antes de aplicar a restrição.
  """

  use Ecto.Migration

  def up do
    alter table(:users) do
      remove :email
      add :nickname, :citext, null: false
    end

    drop_if_exists unique_index(:users, [:email], name: "users_unique_email_index")

    create unique_index(:users, [:nickname], name: "users_unique_nickname_index")
  end

  def down do
    drop_if_exists unique_index(:users, [:nickname], name: "users_unique_nickname_index")

    create unique_index(:users, [:email], name: "users_unique_email_index")

    alter table(:users) do
      remove :nickname
      add :email, :citext, null: false
    end
  end
end
