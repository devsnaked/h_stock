defmodule Web.TotpSession do
  @moduledoc """
  O login que passou pela senha e ainda espera o código de 6 dígitos.

  Entre as duas etapas não existe usuário logado: o que fica guardado é um
  bilhete de espera na sessão (cifrada, ver `Web.Endpoint`) com o token que
  só será instalado quando o código conferir.

  O bilhete morre sozinho em #{10} minutos e depois de 5 tentativas erradas —
  sem isso, um código de 6 dígitos cai por tentativa e erro.
  """
  import Plug.Conn

  @key :totp_pending
  @max_attempts 5
  @ttl_seconds 600

  def max_attempts, do: @max_attempts

  @doc "Guarda o login pendente e o que ele precisa para ser concluído."
  def start(conn, user, token) do
    put_session(conn, @key, %{
      user_id: user.id,
      token: token,
      attempts: 0,
      expires_at: DateTime.add(DateTime.utc_now(), @ttl_seconds, :second)
    })
  end

  @doc "Bilhete válido, ou `:error` se não existe / expirou."
  def fetch(conn) do
    case get_session(conn, @key) do
      %{expires_at: expires_at} = pending ->
        if DateTime.after?(DateTime.utc_now(), expires_at), do: :error, else: {:ok, pending}

      _ ->
        :error
    end
  end

  @doc """
  Conta mais uma tentativa errada.

  Devolve `:blocked` quando estourou o limite — aí o bilhete é descartado e a
  pessoa recomeça pela senha.
  """
  def register_failure(conn, pending) do
    attempts = pending.attempts + 1

    if attempts >= @max_attempts do
      {:blocked, clear(conn)}
    else
      {:ok, put_session(conn, @key, %{pending | attempts: attempts})}
    end
  end

  def clear(conn), do: delete_session(conn, @key)

  # --- Validação da sessão já autenticada -------------------------------
  #
  # Passar pelo código uma vez não vale para sempre: a sessão carrega o
  # instante da última validação e o conteúdo do sistema fica fechado quando
  # ela envelhece. É o que impede um celular esquecido em cima do balcão de
  # continuar aberto o dia inteiro.

  @verified_key :totp_verified_at

  @doc """
  De quanto em quanto tempo o código é pedido de novo, em segundos.

  Uma hora por padrão; `config :h_stock, :totp_revalidation_seconds` ajusta
  (uma loja que fica com o celular no balcão a tarde inteira pode querer
  menos).
  """
  def verification_max_age,
    do: Application.get_env(:h_stock, :totp_revalidation_seconds, 3600)

  @doc """
  A verificação em duas etapas está sendo exigida?

  Chave de exceção (`config :h_stock, :totp_required`), lida em tempo de
  execução de propósito: dá para desligar e religar sem recompilar, e o teste
  consegue exercitar os dois caminhos. Desligada, ninguém é levado para a
  ativação nem tem o conteúdo fechado por código vencido — mas quem já ativou
  não perde nada, e religar volta a exigir o mesmo segredo.
  """
  def required?, do: Application.get_env(:h_stock, :totp_required, true)

  @doc "Marca agora como o instante da última validação bem-sucedida."
  def mark_verified(conn), do: put_session(conn, @verified_key, DateTime.utc_now())

  @doc "A validação desta sessão ainda está de pé?"
  def verified?(conn) do
    case get_session(conn, @verified_key) do
      %DateTime{} = at ->
        DateTime.diff(DateTime.utc_now(), at, :second) < verification_max_age()

      _ ->
        false
    end
  end

  @doc "Quantos segundos faltam para o código ser pedido de novo."
  def seconds_until_expiry(conn) do
    case get_session(conn, @verified_key) do
      %DateTime{} = at ->
        max(verification_max_age() - DateTime.diff(DateTime.utc_now(), at, :second), 0)

      _ ->
        0
    end
  end

  @doc "Descarta a validação — o próximo acesso volta a pedir o código."
  def clear_verification(conn), do: delete_session(conn, @verified_key)
end
