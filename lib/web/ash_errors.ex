defmodule Web.AshErrors do
  @moduledoc """
  Traduz erros do Ash para o formato de validação do Inertia
  (`%{"campo" => "mensagem"}`), mais uma mensagem única para o toast.

  Erros sem campo associado caem em `"form"` — é o que o front mostra acima
  do formulário quando o problema não é de um campo específico.
  """

  @doc "Mapa campo => mensagem, no formato que o `assign_errors/2` espera."
  @spec to_map(term()) :: %{String.t() => String.t()}
  def to_map(error) do
    error
    |> list_errors()
    |> Enum.reduce(%{}, fn error, acc ->
      Map.put_new(acc, field(error), message(error))
    end)
  end

  @doc "Primeira mensagem legível, para o flash/toast."
  @spec summary(term(), String.t()) :: String.t()
  def summary(error, fallback \\ "Não foi possível salvar.") do
    case list_errors(error) do
      [first | _] -> message(first)
      [] -> fallback
    end
  end

  defp list_errors(%{errors: errors}) when is_list(errors), do: List.flatten(errors)
  defp list_errors(errors) when is_list(errors), do: List.flatten(errors)
  defp list_errors(error), do: [error]

  defp field(error) do
    cond do
      is_atom(field = Map.get(error, :field)) and not is_nil(field) -> to_string(field)
      match?([_ | _], Map.get(error, :fields)) -> error.fields |> List.first() |> to_string()
      true -> "form"
    end
  end

  # As mensagens do Ash vêm com placeholders (`%{max}`) resolvidos por `vars`.
  defp message(%{message: message} = error) when is_binary(message) do
    error
    |> Map.get(:vars, [])
    |> Enum.reduce(message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp message(%_{} = error) when is_exception(error), do: Exception.message(error)
  defp message(error), do: inspect(error)
end
