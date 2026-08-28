# Imagem de produção do h_stock.
#
#   - builder: hexpm/elixir (Elixir + Erlang) + Node, compila o release
#   - final:   debian slim, só com o release compilado dentro
#
# As tags vêm do servidor de build do Hex (https://bob.hex.pm/docker). Builder
# e runner usam a mesma versão do Debian de propósito: o release carrega NIFs
# ligadas dinamicamente (bcrypt, exqlite) e elas precisam da mesma libc.

ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.3.4.16
ARG DEBIAN_VERSION=trixie-20260824-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Dependências de build. `nodejs`/`npm` existem por causa do front: o bundle é
# feito pelo esbuild, mas os pacotes do `assets/package.json` (React, Inertia,
# Radix, Leaflet) são baixados pelo npm.
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git nodejs npm \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV="prod"

# Dependências do Elixir primeiro: mudar código não invalida esta camada.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Config de tempo de compilação antes de compilar as dependências, para que
# uma mudança nela realmente force a recompilação.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# `assets.setup` instala tailwind, esbuild e roda `npm install` — por isso o
# package.json vem antes do resto do front: só mexer num `.tsx` não refaz o
# `npm install`.
COPY assets/package.json assets/package-lock.json assets/
RUN mix assets.setup

COPY priv priv
COPY lib lib

RUN mix compile

COPY assets assets
RUN mix assets.deploy

# Mudanças no runtime.exs não exigem recompilar o código.
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# ---------------------------------------------------------------------------

FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     libstdc++6 openssl libncurses6 locales ca-certificates curl tini \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# O diretório do banco. Existe na imagem, e vazio, para que o volume montado
# em cima herde este dono — sem isso o SQLite não consegue escrever rodando
# como `nobody`.
RUN mkdir -p /data && chown nobody:root /data
ENV DATABASE_PATH="/data/h_stock.db"

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/h_stock ./

USER nobody

EXPOSE 4000

# `tini` como PID 1: sem ele o container não recolhe processos zumbis nem
# repassa o sinal de parada direito.
ENTRYPOINT ["/usr/bin/tini", "--"]

# Migra e sobe. Ver `rel/overlays/bin/start`.
CMD ["/app/bin/start"]
