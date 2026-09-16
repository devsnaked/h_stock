#!/usr/bin/env bash
#
# Deploy do h_stock: constrói a imagem aqui, empurra para o servidor e sobe.
#
#   cp deploy.env.example deploy.env   # host, usuário, senha
#   ./deploy.sh                        # constrói, envia, sobe
#   ./deploy.sh --seed                 # idem + cria o admin (primeira vez)
#
# O servidor não precisa do código, nem de Elixir, nem de Node: recebe a
# imagem pronta. A transferência é um cano — `docker save | gzip | ssh |
# docker load` — de propósito: não sobra tarball nenhum nem aqui nem lá.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

COMPOSE_FILE="docker-compose.prod.yml"
IMAGE="h_stock"

# shellcheck source=deploy.lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/deploy.lib.sh"

# --- argumentos ------------------------------------------------------------

SEED=false
FORCE=false

usage() {
  cat <<EOF
uso: ./deploy.sh [opções]

  --seed     roda os seeds depois de subir (cria o admin; é idempotente)
  --force    reconstrói e reenvia mesmo que o servidor já tenha esta versão
  -h         esta ajuda

Configuração em '$CONFIG' (ver deploy.env.example).
Para desmontar tudo no servidor, é o ./teardown.sh.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --seed) SEED=true ;;
    --force) FORCE=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "opção desconhecida: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

carregar_config
preparar_acesso

# --- versão ----------------------------------------------------------------

# A tag é o commit. Árvore suja vira `-dirty` e nunca é considerada "já
# enviada": duas árvores sujas diferentes têm o mesmo commit.
if git rev-parse --git-dir >/dev/null 2>&1; then
  TAG="$(git rev-parse --short HEAD)"
  git diff --quiet && git diff --cached --quiet || TAG="${TAG}-dirty"
else
  TAG="$(date +%Y%m%d-%H%M%S)"
fi

[[ "$TAG" == *-dirty ]] && FORCE=true

echo "==> h_stock:$TAG  ->  $TARGET:$REMOTE_DIR"

# --- pré-requisitos --------------------------------------------------------

command -v docker >/dev/null || { echo "erro: docker não encontrado aqui." >&2; exit 1; }

ssh_run "command -v docker >/dev/null" || {
  echo "erro: o servidor não tem docker instalado." >&2
  exit 1
}

if [ ! -f .env.prod ]; then
  echo "erro: .env.prod não existe aqui." >&2
  echo "      'cp .env.prod.example .env.prod' e preencha — ele é enviado junto." >&2
  exit 1
fi

env_prod() { grep -E "^$1=" .env.prod | head -1 | cut -d= -f2- | tr -d "\"'"; }

for var in SECRET_KEY_BASE TOKEN_SIGNING_SECRET; do
  case "$(env_prod "$var")" in
    "" | troque-me*)
      echo "erro: $var em .env.prod ainda está com o valor de exemplo." >&2
      echo "      gere um com 'mix phx.gen.secret'." >&2
      exit 1
      ;;
  esac
done

# Sem domínio próprio, o endereço sai do próprio IP: o sslip.io resolve
# `203-0-113-10.sslip.io` para `203.0.113.10`. Não é firula — é o que dá ao
# Caddy um *nome* para pedir certificado; para um IP pelado o Let's Encrypt
# não emite, e sem certificado a senha e o código do 2FA iriam em texto claro.
sslip_de() { echo "${1//./-}.sslip.io"; }

phx_host="$(env_prod PHX_HOST)"
case "$phx_host" in
  "" | *exemplo.com.br*)
    echo "erro: PHX_HOST em .env.prod ainda está com o valor de exemplo." >&2
    if [[ "$SERVER_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "      para este servidor: PHX_HOST=$(sslip_de "$SERVER_HOST")" >&2
    fi
    exit 1
    ;;
  *.sslip.io | *.nip.io)
    # Nome derivado de outro IP é o erro clássico de reaproveitar o .env.prod
    # de outra instalação: o Caddy pediria certificado para uma máquina que
    # não é esta, e a tela não abriria.
    ip_no_nome="${phx_host%.sslip.io}"
    ip_no_nome="${ip_no_nome%.nip.io}"
    ip_no_nome="${ip_no_nome//-/.}"
    if [ "$ip_no_nome" != "$SERVER_HOST" ]; then
      echo "aviso: PHX_HOST aponta para $ip_no_nome, e você está entregando em $SERVER_HOST." >&2
    fi
    ;;
esac

# --- já está lá? -----------------------------------------------------------

if [ "$FORCE" = false ] && ssh_run "$DOCKER image inspect $IMAGE:$TAG >/dev/null 2>&1"; then
  echo "==> servidor já tem h_stock:$TAG; pulando build e envio (--force refaz)"
else
  echo "==> construindo a imagem"
  docker build -t "$IMAGE:$TAG" .

  echo "==> enviando (imagem comprimida, direto para o docker do servidor)"
  # A versão anterior fica marcada como `previous` antes da troca: se esta
  # subir quebrada, o caminho de volta é um `docker tag` no servidor.
  ssh_run "$DOCKER image inspect $IMAGE:latest >/dev/null 2>&1 && $DOCKER tag $IMAGE:latest $IMAGE:previous || true"

  docker save "$IMAGE:$TAG" | gzip -1 | ssh_run "gunzip | $DOCKER load"
  ssh_run "$DOCKER tag $IMAGE:$TAG $IMAGE:latest"
fi

# --- arquivos de configuração ----------------------------------------------

echo "==> enviando compose, Caddyfile e .env.prod"
ssh_run "mkdir -p $REMOTE_DIR"
"${SCP[@]}" "$COMPOSE_FILE" Caddyfile .env.prod "$TARGET:$REMOTE_DIR/"
# O .env.prod carrega os segredos: no servidor ele é só do dono.
ssh_run "chmod 600 $REMOTE_DIR/.env.prod"

# --- subir -----------------------------------------------------------------

echo "==> subindo"
# Sem `--build`: a imagem já chegou pronta, e o servidor não tem o código.
compose_remoto "up -d --remove-orphans"

echo "==> esperando o healthcheck"
healthy=false
for _ in $(seq 1 45); do
  status="$(ssh_run "$DOCKER inspect -f '{{.State.Health.Status}}' h_stock 2>/dev/null" || echo unknown)"
  case "$status" in
    healthy) healthy=true; break ;;
    unhealthy) break ;;
  esac
  sleep 2
done

if [ "$healthy" != true ]; then
  echo "erro: o container não ficou saudável (estado: ${status:-?}). Últimas linhas:" >&2
  compose_remoto "logs --tail 40 app" >&2 || true
  echo >&2
  echo "para voltar à versão anterior:" >&2
  echo "  ssh $TARGET 'cd $REMOTE_DIR && docker tag $IMAGE:previous $IMAGE:latest && docker compose -f $COMPOSE_FILE up -d'" >&2
  exit 1
fi

if [ "$SEED" = true ]; then
  echo "==> seeds"
  compose_remoto "exec -T app /app/bin/seed"
fi

# --- limpeza ---------------------------------------------------------------

# Só as imagens antigas do h_stock e o lixo solto do docker. Volume nenhum é
# tocado: é lá que mora o banco.
echo "==> limpando imagens antigas no servidor"
ssh_run "$DOCKER images '$IMAGE' --format '{{.Repository}}:{{.Tag}}' \
  | grep -v -e ':latest\$' -e ':previous\$' -e ':$TAG\$' \
  | xargs -r $DOCKER rmi -f >/dev/null 2>&1 || true"
ssh_run "$DOCKER image prune -f >/dev/null"

echo
echo "pronto: https://$phx_host"
