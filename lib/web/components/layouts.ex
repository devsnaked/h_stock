defmodule Web.Layouts do
  @moduledoc """
  Layouts da camada web.

  Como todas as páginas são renderizadas pelo Inertia (React), o único layout
  que existe aqui é o `root.html.heex`: o esqueleto HTML que carrega o bundle
  e a div raiz do Inertia. Todo o resto do chrome (header, sidebar, toasts)
  mora nos layouts React em `assets/js/layouts/`.
  """
  use Web, :html

  embed_templates "layouts/*"
end
