defmodule Core.Accounts.Totp do
  @moduledoc """
  Verificação em duas etapas por código de 6 dígitos (TOTP, RFC 6238).

  O Google Authenticator é só um dos aplicativos que servem: o padrão é
  aberto, e Authy, 1Password ou Microsoft Authenticator geram o mesmo código
  a partir do mesmo segredo. Nenhum serviço externo participa — a conta e o
  celular calculam o mesmo número a partir do relógio.

  ## Códigos de recuperação

  Perder o celular não pode significar perder a conta. Na ativação são
  gerados 8 códigos de uso único, guardados com o mesmo hash das senhas — o
  banco nunca vê o código em claro, e cada um só funciona uma vez.
  """

  @recovery_code_count 8

  @doc "Segredo novo para uma ativação."
  @spec secret() :: binary()
  def secret, do: NimbleTOTP.secret()

  @doc """
  URI `otpauth://` que vira o QR Code lido pelo aplicativo — e o link que, no
  celular, abre o autenticador direto, sem passar pela câmera.

  O rótulo leva o nickname para a pessoa distinguir esta conta das outras que
  ela já tem no mesmo aplicativo.
  """
  @spec provisioning_uri(binary(), String.t()) :: String.t()
  def provisioning_uri(secret, nickname) do
    issuer = issuer()
    NimbleTOTP.otpauth_uri("#{issuer}:#{nickname}", secret, issuer: issuer)
  end

  @doc """
  O nome exibido pelo aplicativo autenticador (`config :h_stock, :totp_issuer`,
  ou `TOTP_ISSUER`).

  É o rótulo, e só ele: trocá-lo não mexe em segredo nenhum, e quem já ativou
  continua entrando com o mesmo código.
  """
  @spec issuer() :: String.t()
  def issuer, do: Application.get_env(:h_stock, :totp_issuer, "Mercado")

  @doc """
  QR Code da URI como data URI de SVG, pronto para um `<img src=...>`.

  Gerado no servidor de propósito: o segredo não passeia pelo JavaScript, não
  vira dependência de front, e a página não precisa injetar HTML cru.
  """
  @spec qr_code_data_uri(String.t()) :: String.t()
  def qr_code_data_uri(uri) do
    svg =
      uri
      |> EQRCode.encode()
      |> EQRCode.svg(width: 240, background_color: "#ffffff", color: "#000000")

    "data:image/svg+xml;base64," <> Base.encode64(svg)
  end

  @doc """
  O código confere?

  `since` é o instante do último código aceito: passá-lo faz a biblioteca
  recusar o mesmo código duas vezes, então quem espiar a tela por cima do
  ombro não consegue reusá-lo dentro da janela de 30s.
  """
  # Janela de 30s antes e depois da atual.
  #
  # Sem essa folga, um celular com o relógio 20 segundos adiantado nunca
  # consegue entrar — e a pessoa não tem como descobrir o porquê. É a
  # tolerância que a própria RFC 6238 recomenda.
  @accepted_periods [0, -1, 1]

  @spec valid?(binary() | nil, String.t() | nil, DateTime.t() | nil) :: boolean()
  def valid?(nil, _code, _since), do: false
  def valid?(_secret, nil, _since), do: false

  def valid?(secret, code, since) do
    code = String.trim(code)

    # Só tenta se for mesmo 6 dígitos — evita gastar comparação com lixo.
    if String.match?(code, ~r/^\d{6}$/) do
      Enum.any?(@accepted_periods, &valid_at?(secret, code, since, &1))
    else
      false
    end
  end

  defp valid_at?(secret, code, since, periods_offset) do
    time = System.os_time(:second) + periods_offset * 30

    NimbleTOTP.valid?(secret, code, time: time, since: since)
  end

  @doc "Códigos de recuperação novos: os originais (para mostrar uma vez) e os hashes (para guardar)."
  @spec generate_recovery_codes() :: {[String.t()], [String.t()]}
  def generate_recovery_codes do
    codes =
      Enum.map(1..@recovery_code_count, fn _ ->
        4
        |> :crypto.strong_rand_bytes()
        |> Base.encode32(case: :lower, padding: false)
        |> String.slice(0, 6)
      end)

    {codes, Enum.map(codes, &Bcrypt.hash_pwd_salt/1)}
  end

  @doc """
  Confere um código de recuperação contra os hashes guardados.

  Devolve os hashes restantes, sem o que foi usado — código de recuperação é
  de uso único.
  """
  @spec consume_recovery_code([String.t()], String.t() | nil) ::
          {:ok, [String.t()]} | :error
  def consume_recovery_code(_hashes, nil), do: :error

  def consume_recovery_code(hashes, code) do
    code = code |> String.trim() |> String.downcase() |> String.replace("-", "")

    case Enum.find(hashes, &Bcrypt.verify_pass(code, &1)) do
      nil -> :error
      used -> {:ok, List.delete(hashes, used)}
    end
  end
end
