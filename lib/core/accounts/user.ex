defmodule Core.Accounts.User do
  @moduledoc """
  Usuário do sistema. Três perfis:

    * `:admin` — controla estoque, pedidos e os próprios usuários;
    * `:employee` — registra pedidos e, se o admin liberar, também gerencia o
      estoque (`can_manage_stock`), os pedidos da equipe inteira
      (`can_manage_orders`) e o painel da loja (`can_view_dashboard` +
      `dashboard_sections`);
    * `:driver` — entregador. Não registra venda nem enxerga estoque: recebe
      os pedidos que lhe mandam e marca a saída e a entrega.

  Não há cadastro público: o registro pela rota de autenticação está desligado
  (`registration_enabled? false`) e quem cria usuário é o admin.

  **Login é por `nickname`**, não por e-mail: numa loja, nem todo funcionário
  tem (ou lembra) um endereço, e o balcão digita algo curto. Como não há
  e-mail, também não há "esqueci minha senha" por link — quem esquece pede ao
  admin, que define uma nova senha em `set_password`.
  """
  use Ash.Resource,
    otp_app: :h_stock,
    domain: Core.Accounts,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Core.Accounts.Token
      signing_secret Core.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :nickname
        hash_provider AshAuthentication.BcryptProvider
        # Sem auto-cadastro: a rota POST /auth/user/password/register deixa de
        # existir e usuários passam a ser criados pelo admin.
        registration_enabled? false

        # Sem `resettable`: recuperação por link exigiria e-mail, que este
        # sistema não guarda. A saída para senha esquecida é o admin em
        # `/usuarios/:id/senha`.
      end

      # Sem `remember_me`: não existe login de longa duração aqui. Toda visita
      # começa uma sessão nova, e ela morre com o navegador — um celular de
      # balcão passa de mão em mão, e um cookie de semanas é a credencial mais
      # fácil de esquecer aberta. Quem entra, entra pela senha e pelo código.
    end
  end

  sqlite do
    table "users"
    repo Core.Repo
  end

  code_interface do
    define :list, action: :read
    define :list_drivers, action: :drivers
    define :create_user, args: [:nickname, :name, :password, :password_confirmation]
    # Sem args posicionais: são cinco permissões, e cinco booleanos em fila
    # indiana no meio de uma chamada não dizem qual é qual.
    define :set_permissions
    define :set_password, args: [:password, :password_confirmation]
    define :set_active, args: [:active]
    define :start_totp_enrollment
    define :confirm_totp, args: [:code]
    define :disable_totp
    define :register_totp_use
    define :consume_recovery_code, args: [:remaining_hashes]
  end

  actions do
    defaults [:read]

    read :drivers do
      description "Entregadores ativos, na ordem em que aparecem para escolher."

      filter expr(role == :driver and active == true)
      prepare build(sort: [name: :asc])
    end

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    create :create_user do
      description "Criação de usuário pelo admin."

      accept [
        :nickname,
        :name,
        :role,
        :can_manage_stock,
        :can_manage_orders,
        :can_view_dashboard,
        :dashboard_sections
      ]

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)
      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
      change Core.Accounts.Changes.NormalizePermissions
    end

    update :set_permissions do
      description "Troca o perfil e as permissões de estoque, pedidos e painel."
      require_atomic? false

      accept [
        :role,
        :can_manage_stock,
        :can_manage_orders,
        :can_view_dashboard,
        :dashboard_sections
      ]

      change Core.Accounts.Changes.NormalizePermissions
    end

    update :set_active do
      description "Ativa/desativa o acesso do usuário."
      accept [:active]
    end

    update :set_password do
      description "Admin define uma nova senha para o usuário (sem exigir a atual)."
      require_atomic? false
      accept []

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)
      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    update :start_totp_enrollment do
      description "Gera um segredo novo para a pessoa escanear. Ainda não vale para entrar."
      require_atomic? false
      accept []

      change set_attribute(:totp_secret, &Core.Accounts.Totp.secret/0)
      change set_attribute(:totp_confirmed_at, nil)
      change set_attribute(:totp_last_used_at, nil)
      change set_attribute(:totp_recovery_hashes, [])
    end

    update :confirm_totp do
      description "Confere o primeiro código e liga a verificação em duas etapas."
      require_atomic? false
      accept []

      argument :code, :string, allow_nil?: false, sensitive?: true

      # Os códigos de recuperação são devolvidos em claro no metadata: é a
      # única vez que eles existem fora do hash, e a tela precisa mostrá-los.
      metadata :recovery_codes, {:array, :string}

      change Core.Accounts.Changes.ConfirmTotp
    end

    update :disable_totp do
      description "Desliga a verificação em duas etapas e apaga o segredo."
      require_atomic? false
      accept []

      change set_attribute(:totp_secret, nil)
      change set_attribute(:totp_confirmed_at, nil)
      change set_attribute(:totp_last_used_at, nil)
      change set_attribute(:totp_recovery_hashes, [])
    end

    update :register_totp_use do
      description "Marca o instante do código aceito, para ele não valer de novo."
      accept []

      change set_attribute(:totp_last_used_at, &DateTime.utc_now/0)
    end

    update :consume_recovery_code do
      description "Gasta um código de recuperação (uso único)."
      require_atomic? false
      accept []

      argument :remaining_hashes, {:array, :string}, allow_nil?: false, sensitive?: true

      change set_attribute(:totp_recovery_hashes, arg(:remaining_hashes))
    end

    update :change_password do
      description "Usuário troca a própria senha informando a atual."
      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    read :sign_in_with_password do
      description "Entrar com nickname e senha."
      get? true

      argument :nickname, :ci_string do
        description "O nickname usado para achar o usuário."
        allow_nil? false
      end

      argument :password, :string do
        description "The password to check for the matching user."
        allow_nil? false
        sensitive? true
      end

      # Usuário desativado não entra. O filtro roda antes da checagem de senha,
      # então a resposta é a mesma de credencial inválida — nada vaza.
      filter expr(active == true)

      # validates the provided email and password and generates a token
      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    read :sign_in_with_token do
      description "Attempt to sign in using a short-lived sign in token."
      get? true

      argument :token, :string do
        description "The short-lived sign in token."
        allow_nil? false
        sensitive? true
      end

      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # Admin enxerga todo mundo; funcionário só a si mesmo — e os entregadores
    # ativos, porque é para um deles que ele manda o pedido pronto. O que o
    # entregador enxerga da equipe continua sendo só ele mesmo.
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(id == ^actor(:id))
      authorize_if expr(role == :driver and active == true and ^actor(:role) != :driver)
    end

    policy action(:change_password) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action([:create_user, :set_permissions, :set_active, :set_password]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    # Ativar o 2FA é sempre da própria pessoa: ninguém liga a chave do celular
    # de outro.
    policy action([:start_totp_enrollment, :confirm_totp]) do
      authorize_if expr(id == ^actor(:id))
    end

    # Desligar também pode ser feito pelo admin — é a saída para o funcionário
    # que perdeu o celular e gastou os códigos de recuperação.
    policy action(:disable_totp) do
      authorize_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
    end

    # Estas duas rodam no meio do login, quando ainda não existe ator: são
    # chamadas com `authorize?: false` pelo controller, depois de o código já
    # ter sido conferido.
    policy action([:register_totp_use, :consume_recovery_code]) do
      forbid_if always()
    end

    policy action_type(:destroy) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    uuid_primary_key :id

    # Como a pessoa entra. Curto e sem espaço, porque é digitado no balcão,
    # às vezes com a mão ocupada. `ci_string`: "Maria" e "maria" são o mesmo
    # login — ninguém deveria ser barrado porque o teclado do celular
    # capitalizou a primeira letra.
    attribute :nickname, :ci_string do
      description "Login da pessoa. Letras, números, ponto, hífen e underline."
      allow_nil? false
      public? true

      constraints min_length: 3,
                  max_length: 30,
                  trim?: true,
                  match: ~r/^[a-zA-Z0-9._-]+$/
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 2, trim?: true
    end

    attribute :role, :atom do
      constraints one_of: [:admin, :employee, :driver]
      default :employee
      allow_nil? false
      public? true
    end

    # Só faz sentido para `:employee` — admin gerencia estoque por definição.
    # Use a calculation `manages_stock?` em vez deste campo cru.
    attribute :can_manage_stock, :boolean do
      default false
      allow_nil? false
      public? true
    end

    # Alcança os pedidos de toda a equipe, e não só os que a própria pessoa
    # registrou: ver, cancelar e mandar para o entregador. Mesma régua do
    # estoque — admin já tem por definição, entregador nunca tem.
    attribute :can_manage_orders, :boolean do
      default false
      allow_nil? false
      public? true
    end

    # O painel da loja é uma tela de olhar números — e números da loja não são
    # da conta de todo mundo. Sem isto a pessoa nem abre a home: ela começa o
    # dia nos pedidos. Admin abre por definição; entregador nunca.
    attribute :can_view_dashboard, :boolean do
      default false
      allow_nil? false
      public? true
    end

    # Quais seções de dados do painel a pessoa alcança (vendas, horários,
    # produtos, equipe, entrega, estoque, últimos pedidos). Guardar a lista em
    # vez de um booleano por seção é o que deixa uma seção nova nascer sem
    # migração — a lista válida é
    # `Core.Accounts.Permissions.dashboard_sections/0`, e é ela que valida aqui.
    #
    # Vale só com `can_view_dashboard`: `NormalizePermissions` esvazia a lista
    # de quem não abre o painel, para não sobrar permissão pendurada que
    # voltaria a valer sozinha no dia em que alguém religasse a chave.
    attribute :dashboard_sections, {:array, :atom} do
      constraints items: [one_of: Core.Accounts.Permissions.dashboard_sections()]
      default []
      allow_nil? false
      public? true
    end

    attribute :active, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end

    @doc """
    Segredo do TOTP. Existe assim que a pessoa começa a ativação, mas só vale
    depois de `totp_confirmed_at` — quem escaneou o QR e desistiu no meio não
    fica trancado para fora.
    """
    attribute :totp_secret, :binary do
      sensitive? true
    end

    attribute :totp_confirmed_at, :utc_datetime_usec do
      public? true
    end

    # Instante do último código aceito, para o mesmo código não valer duas
    # vezes dentro da janela de 30 segundos.
    attribute :totp_last_used_at, :utc_datetime_usec do
      sensitive? true
    end

    attribute :totp_recovery_hashes, {:array, :string} do
      default []
      allow_nil? false
      sensitive? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  calculations do
    calculate :manages_stock?,
              :boolean,
              expr(role == :admin or can_manage_stock == true) do
      public? true
    end

    calculate :manages_orders?,
              :boolean,
              expr(role == :admin or can_manage_orders == true) do
      public? true
    end

    calculate :views_dashboard?,
              :boolean,
              expr(role == :admin or can_view_dashboard == true) do
      public? true
    end
  end

  identities do
    identity :unique_nickname, [:nickname]
  end
end
