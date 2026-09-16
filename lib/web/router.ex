defmodule Web.Router do
  use Web, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # Preenche `conn.assigns.current_user` a partir do token na sessão. Não há
    # cookie de "manter conectado" para repor sessão nenhuma: sessão expirada
    # volta para o login.
    plug :load_from_session
    plug Inertia.Plug
    # Precisa vir DEPOIS do Inertia.Plug: é ele quem publica os props
    # compartilhados (user, csrfToken, flash) em cima da conn do Inertia.
    plug Web.Plugs.SetCurrentUser
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :require_auth do
    plug Web.Plugs.RequireAuth
    # Estar logado não basta: o conteúdo só abre com o 2FA ativo e validado
    # na última hora.
    plug Web.Plugs.RequireTotp
  end

  pipeline :require_admin do
    plug Web.Plugs.RequireAdmin
  end

  pipeline :require_stock_manager do
    plug Web.Plugs.RequireStockManager
  end

  # As telas de balcão (vender, estoque, resumo da loja) e a tela do
  # entregador são mundos separados: cada plug manda quem errou de porta para
  # a casa certa, em vez de mostrar um erro.
  pipeline :require_counter do
    plug Web.Plugs.RequireCounter
  end

  pipeline :require_driver do
    plug Web.Plugs.RequireDriver
  end

  # O painel é permissão à parte (`can_view_dashboard`), e as seções dentro
  # dele também — quem não o alcança tem a home nos pedidos.
  pipeline :require_dashboard do
    plug Web.Plugs.RequireDashboard
  end

  # Sinal de vida do container e do proxy. Sem pipeline nenhuma: responde
  # antes de sessão, de Inertia e de autenticação.
  scope "/", Web do
    get "/health", HealthController, :index
  end

  # Público: só o que uma pessoa deslogada precisa alcançar.
  scope "/", Web do
    pipe_through :browser

    get "/sign-in", AuthPageController, :sign_in

    # Segunda etapa do login. Fica fora do `:require_auth` porque quem chega
    # aqui ainda NÃO está autenticado — só acertou a senha.
    get "/verificacao", TotpController, :challenge
    post "/verificacao", TotpController, :verify
    post "/verificacao/cancelar", TotpController, :cancel

    # Endpoints do AshAuthentication (só o login). Respondem com redirect, que
    # o Inertia segue normalmente. O registro público está desligado no
    # recurso e não há recuperação por e-mail: quem cria usuário e redefine
    # senha é o admin.
    auth_routes AuthController, Core.Accounts.User, path: "/auth"

    # `sign_out_route/1` também montaria um GET servido por uma LiveView do
    # ash_authentication_phoenix; aqui só o DELETE interessa.
    delete "/sign-out", AuthController, :sign_out
  end

  # O app do entregador.
  scope "/", Web do
    pipe_through [:browser, :require_auth, :require_driver]

    get "/entregas", DeliveryController, :index
  end

  # Escrita no estoque: admin ou funcionário autorizado.
  # Declarado antes das rotas gerais de produto para que `/produtos/novo` não
  # seja capturado por `/produtos/:id`.
  scope "/", Web do
    pipe_through [:browser, :require_auth, :require_stock_manager, :require_counter]

    get "/produtos/novo", ProductController, :new
    post "/produtos", ProductController, :create
    get "/produtos/:id/editar", ProductController, :edit
    put "/produtos/:id", ProductController, :update
    post "/produtos/:id/estoque", ProductController, :move_stock
    post "/produtos/:id/lotes/:batch_id/custo", ProductController, :correct_batch_cost
  end

  # Gestão de usuários e permissões: só admin.
  scope "/", Web do
    pipe_through [:browser, :require_auth, :require_admin]

    get "/usuarios", UserController, :index
    get "/usuarios/novo", UserController, :new
    post "/usuarios", UserController, :create
    get "/usuarios/:id/editar", UserController, :edit
    put "/usuarios/:id", UserController, :update
    post "/usuarios/:id/ativo", UserController, :toggle_active
    post "/usuarios/:id/senha", UserController, :reset_password
    post "/usuarios/:id/2fa/desligar", UserController, :disable_totp

    # O log de auditoria. Fica no mesmo escopo da equipe porque tem a mesma
    # régua: é do administrador e de mais ninguém.
    get "/auditoria", AuditController, :index
  end

  # A análise da loja. Fica sozinha porque é a única tela de balcão com
  # permissão própria; o que se vê dentro dela é decidido seção por seção, no
  # controller.
  scope "/", Web do
    pipe_through [:browser, :require_auth, :require_counter, :require_dashboard]

    get "/", DashboardController, :index
  end

  # O dia a dia de quem trabalha no balcão.
  scope "/", Web do
    pipe_through [:browser, :require_auth, :require_counter]

    get "/pedidos", OrderController, :index
    get "/pedidos/novo", OrderController, :new
    # Antes de `/pedidos/:id`, senão "endereco" viraria um id de pedido.
    get "/pedidos/endereco", OrderController, :geocode
    post "/pedidos", OrderController, :create
    post "/pedidos/:id/cancelar", OrderController, :cancel
    post "/pedidos/:id/entregador", OrderController, :assign_driver

    get "/produtos", ProductController, :index
    get "/produtos/:id", ProductController, :show
  end

  # Rotas de todo mundo, entregador incluído: ele abre o pedido que está com
  # ele e marca a saída e a entrega. Quem alcança qual pedido é a policy do
  # `Core.Orders.Order`, não a rota.
  scope "/", Web do
    pipe_through [:browser, :require_auth]

    get "/pedidos/:id", OrderController, :show
    post "/pedidos/:id/entrega/:estagio", OrderController, :delivery

    get "/seguranca", SecurityController, :show
    post "/seguranca/2fa", SecurityController, :start
    post "/seguranca/2fa/confirmar", SecurityController, :confirm
    post "/seguranca/2fa/desligar", SecurityController, :disable
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:h_stock, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Web.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
