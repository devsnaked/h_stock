# Parte comum ao deploy.sh e ao teardown.sh: ler o `deploy.env` e abrir o
# caminho até o servidor. Não faz nada sozinho — é `source`-ado pelos dois,
# que chamam `carregar_config` e `preparar_acesso` quando já sabem o que vão
# fazer (assim um `-h` não vai bater no servidor à toa).

CONFIG="${DEPLOY_ENV:-deploy.env}"

carregar_config() {
  if [ ! -f "$CONFIG" ]; then
    echo "erro: '$CONFIG' não existe. Comece por 'cp deploy.env.example $CONFIG'." >&2
    exit 1
  fi

  # Lido linha a linha, e não com `source`: senha de verdade tem parêntese,
  # cifrão, aspas — e o shell tentaria executar isso. Aqui o valor entra
  # literal, exatamente como está escrito, e não precisa de aspas nenhuma.
  while IFS= read -r linha || [ -n "$linha" ]; do
    case "$linha" in
      '' | '#'*) continue ;;
    esac

    chave="${linha%%=*}"
    valor="${linha#*=}"
    chave="$(printf '%s' "$chave" | tr -d '[:space:]')"

    # Aspas em volta do valor são cortesia de quem escreveu, não parte da
    # senha: se vieram em par, saem.
    case "$valor" in
      \"*\") valor="${valor#\"}" && valor="${valor%\"}" ;;
      \'*\') valor="${valor#\'}" && valor="${valor%\'}" ;;
    esac

    case "$chave" in
      SERVER_HOST | SERVER_USER | SERVER_PORT | SERVER_PASSWORD | SSH_KEY | SERVER_SUDO | REMOTE_DIR)
        printf -v "$chave" '%s' "$valor"
        ;;
      *)
        echo "aviso: '$CONFIG' tem uma chave que o deploy não conhece: $chave" >&2
        ;;
    esac
  done <"$CONFIG"

  SERVER_HOST="${SERVER_HOST:?defina SERVER_HOST em $CONFIG}"
  SERVER_USER="${SERVER_USER:-root}"
  SERVER_PORT="${SERVER_PORT:-22}"
  SERVER_PASSWORD="${SERVER_PASSWORD:-}"
  SSH_KEY="${SSH_KEY:-}"
  SERVER_SUDO="${SERVER_SUDO:-false}"
  REMOTE_DIR="${REMOTE_DIR:-/opt/h_stock}"
  TARGET="$SERVER_USER@$SERVER_HOST"
}

preparar_acesso() {
  # `ssh`/`scp` com senha precisam do sshpass; sem senha, vale a chave do
  # agente, que é o caminho recomendado.
  SSH=(ssh -p "$SERVER_PORT" -o StrictHostKeyChecking=accept-new)
  SCP=(scp -P "$SERVER_PORT" -o StrictHostKeyChecking=accept-new)

  if [ -n "$SSH_KEY" ]; then
    [ -f "$SSH_KEY" ] || {
      echo "erro: chave '$SSH_KEY' não existe." >&2
      exit 1
    }
    SSH+=(-i "$SSH_KEY" -o IdentitiesOnly=yes)
    SCP+=(-i "$SSH_KEY" -o IdentitiesOnly=yes)
  fi

  if [ -n "$SERVER_PASSWORD" ]; then
    command -v sshpass >/dev/null || {
      echo "erro: SERVER_PASSWORD está definida mas o sshpass não está instalado." >&2
      echo "      instale (apt install sshpass) ou use chave SSH e deixe a senha vazia." >&2
      exit 1
    }
    # Pelo ambiente, não pela linha de comando: argumento de processo é público.
    export SSHPASS="$SERVER_PASSWORD"
    SSH=(sshpass -e "${SSH[@]}")
    SCP=(sshpass -e "${SCP[@]}")
  fi

  # `docker` ou `sudo docker`, conforme o usuário do servidor esteja ou não no
  # grupo docker.
  DOCKER="docker"
  if [ "$SERVER_SUDO" = "true" ]; then
    DOCKER="sudo -n docker"
    if [ -n "$SERVER_PASSWORD" ]; then
      # Aquece o sudo agora, para os comandos seguintes não pararem pedindo
      # senha no meio de um cano de dados.
      ssh_run "sudo -S -v" <<<"$SERVER_PASSWORD" 2>/dev/null || {
        echo "erro: sudo recusou a senha em $TARGET." >&2
        exit 1
      }
    fi
  fi
}

ssh_run() { "${SSH[@]}" "$TARGET" "$@"; }

# O compose do servidor, sempre com o arquivo certo e no diretório certo.
compose_remoto() { ssh_run "cd $REMOTE_DIR && $DOCKER compose -f $COMPOSE_FILE $*"; }
