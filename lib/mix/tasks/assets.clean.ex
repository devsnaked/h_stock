defmodule Mix.Tasks.Assets.Clean do
  @shortdoc "Apaga o bundle gerado em priv/static/assets"

  @moduledoc """
  Limpa a saída do esbuild/tailwind.

  O esbuild só escreve no diretório de saída — nunca remove nada. Como cada
  página vira um chunk com hash no nome, renomear ou apagar uma página deixa o
  chunk antigo para trás. Sem esta limpeza, `mix assets.deploy` mandaria para
  produção (via `phx.digest`) o código de telas que não existem mais.
  """
  use Mix.Task

  @output "priv/static/assets"

  @impl Mix.Task
  def run(_args) do
    File.rm_rf!(@output)
    Mix.shell().info("Limpou #{@output}")
  end
end
