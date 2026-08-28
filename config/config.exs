# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# These enable behaviors that will become the default in the next major
# version of Ash. Setting them now opts your application into the new
# behavior and ensures a seamless upgrade. See the backwards compatibility
# guide for an explanation of each setting:
# https://hexdocs.pm/ash/backwards-compatibility-config.html
config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  many_to_many_destroy_destination_on_match?: true

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :authentication,
        :token,
        :user_identity,
        :sqlite,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

config :h_stock,
  namespace: Core,
  ecto_repos: [Core.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [Core.Accounts, Core.Inventory, Core.Orders, Core.Audit]

# Configure the endpoint
config :h_stock, Web.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: Web.ErrorHTML, json: Web.ErrorJSON],
    layout: false
  ],
  pubsub_server: Core.PubSub,
  live_view: [signing_salt: "+IFEgxO5"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Inertia.js — o front é React puro; o Phoenix só devolve página + props.
# `camelize_props` deixa os props em camelCase do lado JS sem termos de
# renomear nada nos controllers.
config :inertia,
  endpoint: Web.Endpoint,
  static_paths: ["/assets"],
  default_version: "1",
  camelize_props: true,
  ssr: false

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :h_stock, Core.Mailer, adapter: Swoosh.Adapters.Local

# esbuild — bundle do front Inertia/React.
#
# `--splitting` + `--format=esm` fazem cada página em `js/pages/` virar seu
# próprio chunk, carregado sob demanda pelo `import()` dinâmico do resolver
# em `app.tsx`. `process.env.NODE_ENV` precisa ser definido: sem isso o
# bundle do React referencia `process`, que não existe no browser.
config :esbuild,
  version: "0.25.4",
  h_stock: [
    args:
      ~w(js/app.tsx --bundle --splitting --format=esm --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=./js --chunk-names=chunks/[name]-[hash] --asset-names=assets/[name]-[hash] --loader:.png=file --loader:.svg=file --loader:.gif=file --loader:.woff=file --loader:.woff2=file) ++
        [~s(--define:process.env.NODE_ENV="production")],
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  h_stock: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Fuso da operação. O banco guarda tudo em UTC; isto existe para responder
# "o que é hoje?" — sem ele, um pedido das 21h em São Paulo cairia no dia
# seguinte, e o resumo do dia mentiria justamente no fim do expediente.
# O valor efetivo vem de `TIMEZONE` em `config/runtime.exs`; isto é o padrão.
config :h_stock, :timezone, "America/Sao_Paulo"
# `tz` em vez de `tzdata`: a base de fusos é compilada junto do projeto, sem
# cliente HTTP nem download em tempo de execução.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# De quanto em quanto tempo o código de verificação é pedido de novo, em
# segundos. O login continua valendo — o que fecha é o conteúdo.
config :h_stock, :totp_revalidation_seconds, 3600

# A verificação em duas etapas é obrigatória? Ligado é o padrão, e é o que
# deve valer em produção: sem isso, uma senha vazada basta para entrar.
#
# Desligar é uma chave de exceção — desenvolvimento, uma demonstração, ou o
# dia em que a loja inteira perdeu o celular. Nada é apagado: quem já ativou
# continua com o segredo e os códigos de recuperação guardados, e religar a
# chave volta a exigi-los sem ninguém precisar reativar nada.
#
#     TOTP_REQUIRED=false mix phx.server
#
# Lida em `config/runtime.exs` — em produção a variável vale sem recompilar.
config :h_stock, :totp_required, true

# Endereço de entrega no mapa. O Nominatim (OpenStreetMap) não pede chave,
# mas pede um `User-Agent` que identifique quem está chamando — é o que a
# política de uso deles exige de qualquer aplicação.
config :h_stock, :geocoding,
  endpoint: "https://nominatim.openstreetmap.org/search",
  user_agent: "h_stock/1.0 (loja)",
  country: "br"

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
