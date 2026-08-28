import Config
config :h_stock, token_signing_secret: "lsKt6YSpT4ZMtPKTmQnC2IRy9QWDwyvs"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :h_stock, Core.Repo,
  database: Path.expand("../h_stock_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5,
  # O sandbox segura uma transação aberta durante o teste inteiro. Em SQLite
  # só existe um escritor por vez, então um teste que espera o lock espera o
  # outro teste terminar — 30s dão margem sem mascarar um travamento real.
  busy_timeout: 30_000,
  default_transaction_mode: :immediate

# SQLite tem um escritor só. Os testes continuam marcados `async: true` (é o
# que diz que eles não compartilham estado), mas rodam um de cada vez: dois
# sandboxes escrevendo no mesmo arquivo se bloqueiam mutuamente e o segundo
# só destrava quando o primeiro solta — que é o mesmo que serializar, porém
# com timeouts pelo caminho.
config :ex_unit, max_cases: 1

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :h_stock, Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "OYxL03PYpftdx6kZcUC6MIYnycflMDcSiaoggFDk+zp183RiaZVdIZB1YZjk+UlR",
  server: false

# In test we don't send emails
config :h_stock, Core.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
