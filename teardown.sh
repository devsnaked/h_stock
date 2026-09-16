#!/usr/bin/env bash
#
# Desmonta o h_stock do servidor — depois de trazer o banco para cá.
#
#   ./teardown.sh                    # baixa o backup e pergunta antes de apagar
#   ./teardown.sh --saida ~/bkp.db   # escolhe onde salvar
#   ./teardown.sh -y                 # sem perguntar (para automação)
#   ./teardown.sh --sem-backup       # quando não há o que salvar
#
# A ordem importa e é o ponto do script: o banco vem primeiro, é conferido
# aqui (tamanho e assinatura de arquivo SQLite), e só então o servidor é
# desmontado. O que se apaga lá não tem desfazer — `h_stock_data` é o sistema
# inteiro: pedidos, produtos, usuários e as ativações de 2FA.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

COMPOSE_FILE="docker-compose.prod.yml"
IMAGE="h_stock"

# shellcheck source=deploy.lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/deploy.lib.sh"

# --- argumentos ------------------------------------------------------------

DESTINO=""
CONFIRMADO=false
BACKUP=true

usage() {
  cat <<EOF
uso: ./teardown.sh [opções]

  --saida <arquivo>   onde salvar o banco (padrão: ./backups/h_stock-<data>.db)
  --sem-backup        pula o download; só desmonta
  -y                  não pergunta antes de apagar
  -h                  esta ajuda

Configuração em '$CONFIG' (ver deploy.env.example).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --saida)
      DESTINO="${2:?--saida precisa de um caminho}"
      shift
      ;;
    --sem-backup) BACKUP=false ;;
    -y | --sim) CONFIRMADO=true ;;
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

echo "==> $TARGET:$REMOTE_DIR"

# --- o banco vem primeiro --------------------------------------------------

if [ "$BACKUP" = true ]; then
  DESTINO="${DESTINO:-backups/h_stock-$(date +%Y%m%d-%H%M%S).db}"
  mkdir -p "$(dirname "$DESTINO")"

  echo "==> gerando a cópia no servidor"
  # `bin/backup` é `VACUUM INTO` por dentro: com o WAL ligado, copiar o
  # arquivo cru traria um banco pela metade.
  remoto="$(compose_remoto "exec -T app /app/bin/backup" | tr -d '\r')" || {
    echo "erro: não consegui gerar o backup — a aplicação está de pé lá?" >&2
    echo "      se ela já morreu e o banco não importa mais, use --sem-backup." >&2
    exit 1
  }

  echo "==> trazendo $remoto"
  # Direto do container para o seu disco, sem escala: nada fica no servidor.
  compose_remoto "exec -T app cat '$remoto'" >"$DESTINO"

  # Conferir antes de destruir. Um arquivo vazio, ou o texto de um erro que
  # tenha vazado pelo cano, não é backup nenhum.
  tamanho=$(wc -c <"$DESTINO")
  assinatura=$(head -c 15 "$DESTINO" || true)
  if [ "$tamanho" -lt 4096 ] || [ "$assinatura" != "SQLite format 3" ]; then
    echo "erro: '$DESTINO' não parece um banco SQLite ($tamanho bytes). Nada foi apagado." >&2
    exit 1
  fi

  echo "==> backup em $DESTINO ($(numfmt --to=iec "$tamanho" 2>/dev/null || echo "$tamanho bytes"))"
fi

# --- confirmação -----------------------------------------------------------

if [ "$CONFIRMADO" != true ]; then
  echo
  echo "Isto apaga do servidor os containers, as imagens, o diretório"
  echo "$REMOTE_DIR (com o .env.prod) e o volume do banco. Não tem desfazer."
  [ "$BACKUP" = true ] && echo "O backup já está aqui: $DESTINO"
  echo
  read -r -p "Digite o endereço do servidor para confirmar ($SERVER_HOST): " resposta
  if [ "$resposta" != "$SERVER_HOST" ]; then
    echo "não confere; nada foi apagado." >&2
    exit 1
  fi
fi

# --- desmontar -------------------------------------------------------------

echo "==> derrubando containers, rede, volumes e imagens dos serviços"
compose_remoto "down -v --rmi all --remove-orphans" || {
  echo "aviso: o compose reclamou — seguindo para a limpeza do que sobrou." >&2
}

echo "==> apagando as imagens do h_stock que sobraram"
ssh_run "$DOCKER images '$IMAGE' --format '{{.Repository}}:{{.Tag}}' | xargs -r $DOCKER rmi -f >/dev/null 2>&1 || true"

echo "==> apagando $REMOTE_DIR"
# Guarda contra um REMOTE_DIR vazio ou `/` num deploy.env mal preenchido.
case "$REMOTE_DIR" in
  "" | "/" | "/*" ) echo "erro: REMOTE_DIR inseguro ('$REMOTE_DIR'); não apaguei." >&2; exit 1 ;;
esac
ssh_run "rm -rf '$REMOTE_DIR'"

echo
echo "pronto: o h_stock saiu de $TARGET."
[ "$BACKUP" = true ] && echo "o banco está em $DESTINO"
echo "para subir de novo: ./deploy.sh --seed"
