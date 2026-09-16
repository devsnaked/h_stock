# Dados iniciais.
#
#     mix ecto.setup                 # já roda este arquivo
#     mix run priv/repo/seeds.exs
#     bin/seed                       # dentro do release, em produção
#
# **Em produção nasce só o administrador.** Ele é o único registro que o
# sistema não consegue criar por dentro: não há cadastro público, então sem
# ele não existe forma de entrar. Produtos, funcionários e entregadores nascem
# das telas, pelas mãos dele.
#
# **Em desenvolvimento vem também a loja de exemplo** (`Core.Demo`): tela
# vazia não se avalia. Para as vendas — que é o que dá o que mostrar ao
# painel — a tarefa é `mix demo.orders`.
#
# É idempotente, e não mexe em quem já existe: rodar de novo depois de trocar
# a senha do admin não a reverte.

require Ash.Query

alias Core.Accounts.User

# `Mix` não existe dentro de um release: em produção esta linha é `false` sem
# depender de ninguém lembrar de passar variável nenhuma.
dev? = Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :dev

nickname = System.get_env("ADMIN_NICKNAME", "admin")

# Sem `ADMIN_PASSWORD`, a senha é sorteada e mostrada uma única vez.
#
# Uma senha padrão escrita aqui seria uma senha pública — quem tem o
# repositório teria a senha do administrador de qualquer instalação que
# esquecesse de trocá-la.
{password, sorteada?} =
  case System.get_env("ADMIN_PASSWORD") do
    valor when valor in [nil, ""] ->
      {24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false), true}

    valor ->
      {valor, false}
  end

existente =
  User
  |> Ash.Query.filter(nickname == ^nickname)
  |> Ash.read_one!(authorize?: false)

admin =
  if existente do
    IO.puts("""

    O administrador `#{nickname}` já existe — a senha dele continua a que está
    valendo. Para trocá-la, é em /usuarios.
    """)

    existente
  else
    novo =
      User.create_user!(
        nickname,
        "Administrador",
        password,
        password,
        %{role: :admin},
        authorize?: false
      )

    aviso =
      if sorteada? do
        "\n  Esta senha foi sorteada agora e NÃO é mostrada de novo.\n  Guarde-a antes de fechar este terminal.\n"
      else
        ""
      end

    IO.puts("""

    Administrador criado.

      login: #{nickname}
      senha: #{password}
    #{aviso}
    A verificação em duas etapas é pedida no primeiro login: tenha o aplicativo
    autenticador à mão.
    """)

    novo
  end

if dev? do
  Core.Demo.ensure_cast(admin)

  IO.puts("""
  Loja de exemplo (só em desenvolvimento):

    funcionario   senha: #{Core.Demo.password()}   (painel liberado)
    entregador    senha: #{Core.Demo.password()}
    3 produtos com estoque

  Para o painel ter o que mostrar, gere as vendas: mix demo.orders
  """)
end
