defmodule Core.Geocoding do
  @moduledoc """
  Endereço digitado no balcão vira coordenada.

  Usa o Nominatim (OpenStreetMap): é gratuito, não pede chave e cobre bem os
  endereços brasileiros. Em troca, pede educação — um `User-Agent` que
  identifique a aplicação e no máximo uma consulta por segundo, que é o que a
  tela faz naturalmente (busca só quando a pessoa pede, não a cada tecla).

  O que sai daqui é uma lista de candidatos; quem escolhe é a pessoa, porque
  "rua das flores 100" acha meia dúzia de cidades e a primeira nem sempre é a
  certa. As coordenadas escolhidas ficam gravadas no pedido, então a entrega
  não depende deste serviço responder de novo.

  Configuração em `config :h_stock, :geocoding` (`endpoint`, `user_agent`,
  `country`).
  """

  require Logger

  @defaults [
    endpoint: "https://nominatim.openstreetmap.org/search",
    user_agent: "h_stock/1.0 (sistema interno de loja)",
    country: "br"
  ]

  @type place :: %{label: String.t(), lat: float(), lon: float()}

  @doc """
  Procura o endereço e devolve até cinco candidatos.

  Serviço fora do ar, lento ou com resposta estranha vira `{:error, :unavailable}`:
  a tela continua funcionando sem mapa, e o pedido é registrado do mesmo
  jeito — endereço no papel sempre foi suficiente para entregar.
  """
  @spec search(String.t()) :: {:ok, [place()]} | {:error, :unavailable}
  def search(query) when is_binary(query) do
    case String.trim(query) do
      "" ->
        {:ok, []}

      trimmed ->
        request(trimmed)
    end
  end

  defp request(query) do
    params = [
      q: query,
      format: "jsonv2",
      limit: 5,
      addressdetails: 0,
      countrycodes: config(:country),
      "accept-language": "pt-BR"
    ]

    case Req.get(config(:endpoint),
           params: params,
           headers: [{"user-agent", config(:user_agent)}],
           receive_timeout: 6_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        {:ok, Enum.flat_map(body, &place/1)}

      {:ok, %{status: status}} ->
        Logger.warning("Geocodificação respondeu #{status}")
        {:error, :unavailable}

      {:error, reason} ->
        Logger.warning("Geocodificação indisponível: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end

  # Resposta sem coordenada legível é descartada em silêncio: um candidato
  # sem ponto no mapa não serve para nada na tela.
  defp place(%{"display_name" => label, "lat" => lat, "lon" => lon}) do
    with {lat, _} <- Float.parse(to_string(lat)),
         {lon, _} <- Float.parse(to_string(lon)) do
      [%{label: label, lat: lat, lon: lon}]
    else
      _ -> []
    end
  end

  defp place(_entry), do: []

  defp config(key) do
    :h_stock
    |> Application.get_env(:geocoding, [])
    |> Keyword.get(key, @defaults[key])
  end
end
