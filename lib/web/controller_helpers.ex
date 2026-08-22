defmodule Web.ControllerHelpers do
  @moduledoc """
  Utilidades compartilhadas pelos controllers: quem é o ator, conversão dos
  números que chegam do formulário e o caminho de erro padrão.
  """
  import Phoenix.Controller
  import Inertia.Controller

  alias Web.AshErrors

  @doc "Usuário autenticado da requisição — o ator de toda chamada ao domínio."
  def actor(conn), do: conn.assigns[:current_user]

  @doc """
  Quem enxerga custo e lucro.

  É a mesma régua do histórico de movimentações (policy do
  `Core.Inventory.StockMovement`): admin ou funcionário autorizado a mexer no
  estoque. Os serializers usam isso para simplesmente não mandar os campos de
  dinheiro de compra para quem não é do grupo.
  """
  def manages_stock?(%{role: :admin}), do: true
  def manages_stock?(%{can_manage_stock: true}), do: true
  def manages_stock?(_user), do: false

  @doc """
  Quem alcança os pedidos da equipe inteira.

  Sem isto o funcionário só enxerga (e cancela, e despacha) o que ele mesmo
  registrou — a policy do `Core.Orders.Order` é quem garante; aqui é só para
  a tela saber o que oferecer.
  """
  def manages_orders?(%{role: :admin}), do: true
  def manages_orders?(%{can_manage_orders: true}), do: true
  def manages_orders?(_user), do: false

  @doc """
  Quem abre o painel da loja.

  A régua mora em `Core.Accounts.Permissions` porque o painel não é só uma
  tela: a lista de seções vale para o serializer, para o plug e para o
  formulário de permissões. Aqui é só o atalho para os controllers lerem igual
  às outras permissões.
  """
  defdelegate views_dashboard?(user), to: Core.Accounts.Permissions

  @doc """
  As seções de dados do painel liberadas para esta pessoa, na ordem da tela.

  É por esta lista que o painel monta os props: o que não está nela não é
  calculado nem publicado.
  """
  defdelegate dashboard_sections(user), to: Core.Accounts.Permissions

  @doc """
  Devolve o usuário para a página de origem com os erros do Ash: mensagem
  única no toast, erros por campo no formulário.

  O Inertia preserva o estado do componente quando a resposta traz erros de
  validação, então o que a pessoa digitou continua lá.
  """
  def fail(conn, error, path) do
    conn
    |> assign_errors(AshErrors.to_map(error))
    |> put_flash(:error, AshErrors.summary(error))
    |> redirect(to: path)
  end

  @doc """
  Busca um registro respeitando as policies.

  Devolve `:error` tanto para id inexistente quanto para registro que o ator
  não pode ver — de propósito: para quem não tem acesso, o recurso não existe,
  e a resposta não revela a diferença.
  """
  def fetch(resource, id, opts) do
    case Ash.get(resource, id, opts) do
      {:ok, record} -> {:ok, record}
      {:error, _reason} -> :error
    end
  end

  @doc "Resposta padrão para registro inexistente ou fora do alcance do ator."
  def not_found(conn, path, message \\ "Registro não encontrado.") do
    conn
    |> put_flash(:error, message)
    |> redirect(to: path)
  end

  @doc """
  Intervalo de datas pedido pela tela (`?de=…&ate=…`), em datas locais.

  Data faltando ou ilegível cai no padrão (`default`, normalmente hoje) em vez
  de virar erro: intervalo é filtro de visualização, não formulário — um link
  velho ou uma URL editada à mão devem mostrar algo, não uma tela de erro.
  Datas invertidas são trocadas de lugar.
  """
  def date_range(params, default \\ nil) do
    default = default || {Core.Clock.today(), Core.Clock.today()}
    {default_from, default_to} = default

    from = parse_date(params["de"], default_from)
    to = parse_date(params["ate"], default_to)

    if Date.compare(from, to) == :gt, do: {to, from}, else: {from, to}
  end

  defp parse_date(value, fallback) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> fallback
    end
  end

  defp parse_date(_value, fallback), do: fallback

  @doc """
  Número digitado no formulário para `Decimal`.

  Aceita vírgula decimal (`"1,5"`), que é como se digita num teclado
  brasileiro. Devolve `nil` quando vazio e `:error` quando não é número.
  """
  def to_decimal(nil), do: nil
  def to_decimal(%Decimal{} = decimal), do: decimal
  def to_decimal(value) when is_integer(value), do: Decimal.new(value)
  def to_decimal(value) when is_float(value), do: Decimal.from_float(value)

  def to_decimal(value) when is_binary(value) do
    case value |> String.trim() |> String.replace(",", ".") do
      "" ->
        nil

      normalized ->
        case Decimal.parse(normalized) do
          {decimal, ""} -> decimal
          _ -> :error
        end
    end
  end

  def to_decimal(_value), do: :error

  @doc "Converte uma quantidade digitada em `:g` ou `:kg` para gramas."
  def to_grams(quantity, unit) do
    case to_decimal(quantity) do
      %Decimal{} = decimal ->
        if unit in ["kg", :kg], do: Decimal.mult(decimal, 1000), else: decimal

      other ->
        other
    end
  end

  @doc """
  Preço digitado na unidade do produto para preço por grama, que é como o
  estoque guarda.
  """
  def to_price_per_gram(price, unit) do
    case to_decimal(price) do
      %Decimal{} = decimal ->
        if unit in ["kg", :kg], do: Decimal.div(decimal, 1000), else: decimal

      other ->
        other
    end
  end

  @doc "Atalho para `nil`/`:error` virarem um erro de formulário legível."
  def invalid_number?(value), do: value == :error
end
