import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/h_stock start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :h_stock, Web.Endpoint, server: true
end

config :h_stock, Web.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Configuração vinda do ambiente, válida em qualquer env. Fica aqui, e não em
# `config/config.exs`, porque `config.exs` é lido em tempo de compilação: numa
# imagem Docker, uma variável definida só no `docker compose` não chegaria a
# tempo de mudar nada.
config :h_stock, :timezone, System.get_env("TIMEZONE", "America/Sao_Paulo")

config :h_stock, :totp_required, System.get_env("TOTP_REQUIRED", "true") == "true"

config :h_stock, :totp_issuer, System.get_env("TOTP_ISSUER", "Mercado")

# O Nominatim (OpenStreetMap) exige um `User-Agent` que identifique a
# aplicação; em produção vale pôr um contato real, é o que a política de uso
# deles pede.
# `config/2` mescla listas de palavras-chave: só o `user_agent` é trocado, o
# `endpoint` e o `country` continuam vindo de `config/config.exs`.
config :h_stock, :geocoding,
  user_agent: System.get_env("GEOCODING_USER_AGENT", "h_stock/1.0 (loja)")

if config_env() == :prod do
  # SQLite: o banco é um arquivo no disco da máquina que roda a aplicação.
  # `DATABASE_PATH` precisa apontar para um volume persistente — num container
  # sem volume montado, o banco some junto com o container.
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /data/h_stock.db
      """

  config :h_stock, Core.Repo,
    database: database_path,
    # SQLite serializa escritas; o pool existe para as leituras.
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    # Espera pelo lock de escrita antes de desistir, em milissegundos.
    busy_timeout: String.to_integer(System.get_env("DB_BUSY_TIMEOUT") || "5000"),
    # `:immediate` pega o lock de escrita já no BEGIN. É o que garante que uma
    # venda leia o saldo que vai alterar: no modo padrão (`:deferred`) duas
    # transações leem juntas e a segunda só descobre o problema ao escrever.
    default_transaction_mode: :immediate

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :h_stock, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :h_stock, Web.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :h_stock,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        raise("Missing environment variable `TOKEN_SIGNING_SECRET`!")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :h_stock, Web.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :h_stock, Web.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :h_stock, Core.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
