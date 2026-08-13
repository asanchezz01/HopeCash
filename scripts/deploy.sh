#!/usr/bin/env bash
# Publica o HopeCash com Docker Compose a partir de um checkout do repositorio.
# Roda no servidor de producao — acionado por SSH pelo GitHub Actions
# (.github/workflows/deploy.yml) ou pelo script local (scripts/deploy-server.ps1).
#
# Entradas (variaveis de ambiente, todas opcionais):
#   ENV_FILE                        .env persistente (padrao /opt/hopecash/.env)
#   WEB_PORT / API_PORT / MYSQL_PORT  forcam portas; senao usa o .env ou a primeira livre
#   API_BASE_URL / CORS_ALLOWED_ORIGINS
#   COMPOSE_FILES                    lista de arquivos Compose separados por espaco
#   NO_CACHE=1  PULL=1  PRUNE=1  RESET_DB=1
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-/opt/hopecash/.env}"
NO_CACHE="${NO_CACHE:-0}"
PULL="${PULL:-0}"
PRUNE="${PRUNE:-0}"
RESET_DB="${RESET_DB:-0}"
COMPOSE_FILES="${COMPOSE_FILES:-docker-compose.yml docker-compose.vps.yml}"
DEPLOY_BACKUP_DIR="${DEPLOY_BACKUP_DIR:-/opt/hopecash/backups/deploy}"

# Guarda as entradas antes de carregar o .env, que usa os mesmos nomes.
WEB_PORT_IN="${WEB_PORT:-}"
API_PORT_IN="${API_PORT:-}"
MYSQL_PORT_IN="${MYSQL_PORT:-}"
RETAGUARDA_PORT_IN="${RETAGUARDA_PORT:-}"
API_BASE_URL_IN="${API_BASE_URL:-}"
CORS_IN="${CORS_ALLOWED_ORIGINS:-}"
BUILD_REF_IN="${BUILD_REF:-}"
BUILD_TIME_IN="${BUILD_TIME:-}"

first_free() {
  for port in "$@"; do
    if ! ss -tuln | grep -Eq ":${port}[[:space:]]"; then
      echo "$port"
      return 0
    fi
  done
  return 1
}

random_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    date +%s%N | sha256sum | awk '{print $1}'
  fi
}

# Carrega o .env persistente SEM executa-lo (source quebra em valores com espaco,
# ex.: SUPERUSER_NAME="Super Admin" ou senhas de app do Gmail). Parser tolerante:
# le KEY=VALUE, ignora comentarios/linhas vazias e remove aspas externas.
if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    key=${line%%=*}
    val=${line#*=}
    val=${val#\"}; val=${val%\"}
    val=${val#\'}; val=${val%\'}
    export "$key=$val"
  done < "$ENV_FILE"
fi

WEB_PORT="${WEB_PORT_IN:-${WEB_PORT:-}}"
API_PORT="${API_PORT_IN:-${API_PORT:-}}"
MYSQL_PORT="${MYSQL_PORT_IN:-${MYSQL_PORT:-}}"
RETAGUARDA_PORT="${RETAGUARDA_PORT_IN:-${RETAGUARDA_PORT:-}}"

if [ -z "$WEB_PORT" ]; then WEB_PORT=$(first_free 8092 8093 8083 8084 8094 8095); fi
if [ -z "$API_PORT" ]; then API_PORT=$(first_free 3001 3002 3003 3010 3011); fi
if [ -z "$MYSQL_PORT" ]; then MYSQL_PORT=$(first_free 3306 3307 3308 3310); fi
# Porta fixa da retaguarda (8085): mantem a origem de CORS estavel entre deploys.
# Sobrescreva com a variavel RETAGUARDA_PORT no .env ou no ambiente, se preciso.
if [ -z "$RETAGUARDA_PORT" ]; then RETAGUARDA_PORT=8085; fi

# No VPS apenas o Nginx Proxy Manager publica portas externamente. Aplicacao e
# banco ficam acessiveis somente por loopback/rede Docker.
WEB_BIND_ADDRESS="${WEB_BIND_ADDRESS:-127.0.0.1}"
API_BIND_ADDRESS="${API_BIND_ADDRESS:-127.0.0.1}"
MYSQL_BIND_ADDRESS="${MYSQL_BIND_ADDRESS:-127.0.0.1}"
RETAGUARDA_BIND_ADDRESS="${RETAGUARDA_BIND_ADDRESS:-127.0.0.1}"
NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-81}"

API_BASE_URL="${API_BASE_URL_IN:-${API_BASE_URL:-https://api.hopecash.tech}}"
CORS_ALLOWED_ORIGINS="${CORS_IN:-${CORS_ALLOWED_ORIGINS:-https://app.hopecash.tech,https://adm.hopecash.tech,https://api.hopecash.tech}}"

# Garante que a origem web da retaguarda (porta dinamica) esteja no CORS, mesmo
# quando um CORS_ALLOWED_ORIGINS pre-existente foi herdado do .env do servidor.
ensure_origin() {
  local origin="$1"
  case ",$CORS_ALLOWED_ORIGINS," in
    *",$origin,"*) ;;
    *) CORS_ALLOWED_ORIGINS="${CORS_ALLOWED_ORIGINS:+$CORS_ALLOWED_ORIGINS,}$origin" ;;
  esac
}
ensure_origin "https://app.hopecash.tech"
ensure_origin "https://adm.hopecash.tech"

# Metadados de versao/build — permitem confirmar, no rodape do dashboard, qual
# commit esta efetivamente publicado em cada container. Recalculados a cada deploy.
BUILD_REF="${BUILD_REF_IN:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}"
BUILD_REF="${BUILD_REF:0:12}"
BUILD_TIME="${BUILD_TIME_IN:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

MYSQL_DATABASE="${MYSQL_DATABASE:-hopecash}"
MYSQL_USER="${MYSQL_USER:-hopecash}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(random_hex)}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(random_hex)}"
JWT_SECRET="${JWT_SECRET:-$(random_hex)$(random_hex)}"

# Retaguarda e e-mail — preservados do .env existente (edite o arquivo do
# servidor para ativar o envio real e trocar a senha do superusuário).
SUPERUSER_EMAIL="${SUPERUSER_EMAIL:-admin@hopecash.app}"
SUPERUSER_NAME="${SUPERUSER_NAME:-Super Admin}"
SUPERUSER_PASSWORD="${SUPERUSER_PASSWORD:-newhope}"
MAIL_ENABLED="${MAIL_ENABLED:-false}"
MAIL_SMTP="${MAIL_SMTP:-smtp.gmail.com}"
MAIL_PORT="${MAIL_PORT:-587}"
MAIL_USER="${MAIL_USER:-}"
MAIL_PASS="${MAIL_PASS:-}"
MAIL_FROM="${MAIL_FROM:-}"
MAIL_USE_TLS="${MAIL_USE_TLS:-true}"
SUPPORT_EMAIL_TO="${SUPPORT_EMAIL_TO:-${MAIL_FROM:-${MAIL_USER:-suporte@hopecash.app}}}"
SUPPORT_EMAIL_SUBJECT_PREFIX="${SUPPORT_EMAIL_SUBJECT_PREFIX:-[HopeCash Suporte]}"
SUPPORT_RATE_LIMIT_MAX="${SUPPORT_RATE_LIMIT_MAX:-5}"
SUPPORT_RATE_LIMIT_WINDOW_MINUTES="${SUPPORT_RATE_LIMIT_WINDOW_MINUTES:-15}"

# Hope: credenciais permanecem exclusivamente no .env do VPS. O workflow envia
# codigo, nunca segredos. Valores vazios fazem os healthchecks reportarem a
# indisponibilidade do provedor sem expor as chaves.
AI_ENABLED="${AI_ENABLED:-false}"
AI_PROVIDER="${AI_PROVIDER:-groq}"
GROQ_API_KEY="${GROQ_API_KEY:-}"
GROQ_BASE_URL="${GROQ_BASE_URL:-https://api.groq.com/openai/v1}"
GROQ_TIMEOUT_MS="${GROQ_TIMEOUT_MS:-30000}"
GROQ_REASONING_EFFORT="${GROQ_REASONING_EFFORT:-low}"
GROQ_MODEL="${GROQ_MODEL:-openai/gpt-oss-120b}"
GROQ_MODEL_CHAT="${GROQ_MODEL_CHAT:-$GROQ_MODEL}"
GROQ_MODEL_FAST="${GROQ_MODEL_FAST:-openai/gpt-oss-20b}"
TTS_ENABLED="${TTS_ENABLED:-false}"
TTS_PROVIDER="${TTS_PROVIDER:-azure}"
AZURE_SPEECH_KEY="${AZURE_SPEECH_KEY:-}"
AZURE_SPEECH_REGION="${AZURE_SPEECH_REGION:-brazilsouth}"
AZURE_SPEECH_ENDPOINT="${AZURE_SPEECH_ENDPOINT:-}"
AZURE_SPEECH_TTS_URL="${AZURE_SPEECH_TTS_URL:-}"
AZURE_SPEECH_VOICES_URL="${AZURE_SPEECH_VOICES_URL:-}"
AZURE_SPEECH_VOICE="${AZURE_SPEECH_VOICE:-pt-BR-ThalitaMultilingualNeural}"
TTS_FORMAT="${TTS_FORMAT:-mp3}"
TTS_SPEED="${TTS_SPEED:-0.96}"
TTS_TIMEOUT_MS="${TTS_TIMEOUT_MS:-45000}"
TTS_MAX_CHARS="${TTS_MAX_CHARS:-4000}"

# Notificacoes push (Firebase Cloud Messaging) — preservadas do .env existente
# no servidor (o operador preenche uma vez em /opt/hopecash/.env; ver
# docs/FLUTTERFIRE.md). Sem valor aqui, o push segue desabilitado (dry-run).
FIREBASE_ENABLED="${FIREBASE_ENABLED:-false}"
FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-hopecash}"
FIREBASE_CLIENT_EMAIL="${FIREBASE_CLIENT_EMAIL:-}"
FIREBASE_PRIVATE_KEY_BASE64="${FIREBASE_PRIVATE_KEY_BASE64:-}"
PUSH_SCHEDULER_ENABLED="${PUSH_SCHEDULER_ENABLED:-false}"
PUSH_SCHEDULER_INTERVAL_MS="${PUSH_SCHEDULER_INTERVAL_MS:-60000}"
PUSH_DUE_REMINDER_DAYS="${PUSH_DUE_REMINDER_DAYS:-3}"
PUSH_DEFAULT_TIMEZONE="${PUSH_DEFAULT_TIMEZONE:-America/Sao_Paulo}"
# URL publica do app Web/PWA — usada so para montar o botao de acao do e-mail
# de fallback (usuario sem nenhum dispositivo push ativo).
PUSH_EMAIL_APP_URL="${PUSH_EMAIL_APP_URL:-}"
# Config publica do app Web/PWA no Firebase (nao e segredo, so ainda nao setada).
FIREBASE_MESSAGING_SENDER_ID="${FIREBASE_MESSAGING_SENDER_ID:-71481307234}"
FIREBASE_WEB_APP_ID="${FIREBASE_WEB_APP_ID:-1:71481307234:web:c284cb740f37342f9a613b}"
FIREBASE_STORAGE_BUCKET="${FIREBASE_STORAGE_BUCKET:-hopecash.firebasestorage.app}"
FIREBASE_WEB_AUTH_DOMAIN="${FIREBASE_WEB_AUTH_DOMAIN:-hopecash.firebaseapp.com}"
FIREBASE_WEB_API_KEY="${FIREBASE_WEB_API_KEY:-}"
FIREBASE_VAPID_KEY="${FIREBASE_VAPID_KEY:-}"

mkdir -p "$(dirname "$ENV_FILE")"
previous_env_tmp="$(mktemp)"
if [ -f "$ENV_FILE" ]; then
  cp "$ENV_FILE" "$previous_env_tmp"
else
  : > "$previous_env_tmp"
fi
cat > "$ENV_FILE" <<EOF
COMPOSE_PROJECT_NAME=hopecash
BUILD_REF=$BUILD_REF
BUILD_TIME=$BUILD_TIME
WEB_PORT=$WEB_PORT
API_PORT=$API_PORT
MYSQL_PORT=$MYSQL_PORT
RETAGUARDA_PORT=$RETAGUARDA_PORT
WEB_BIND_ADDRESS=$WEB_BIND_ADDRESS
API_BIND_ADDRESS=$API_BIND_ADDRESS
MYSQL_BIND_ADDRESS=$MYSQL_BIND_ADDRESS
RETAGUARDA_BIND_ADDRESS=$RETAGUARDA_BIND_ADDRESS
NPM_ADMIN_PORT=$NPM_ADMIN_PORT
API_BASE_URL=$API_BASE_URL
CORS_ALLOWED_ORIGINS=$CORS_ALLOWED_ORIGINS
MYSQL_DATABASE=$MYSQL_DATABASE
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
JWT_SECRET=$JWT_SECRET
SUPERUSER_EMAIL=$SUPERUSER_EMAIL
SUPERUSER_NAME=$SUPERUSER_NAME
SUPERUSER_PASSWORD=$SUPERUSER_PASSWORD
MAIL_ENABLED=$MAIL_ENABLED
MAIL_SMTP=$MAIL_SMTP
MAIL_PORT=$MAIL_PORT
MAIL_USER=$MAIL_USER
MAIL_PASS=$MAIL_PASS
MAIL_FROM=$MAIL_FROM
MAIL_USE_TLS=$MAIL_USE_TLS
SUPPORT_EMAIL_TO=$SUPPORT_EMAIL_TO
SUPPORT_EMAIL_SUBJECT_PREFIX=$SUPPORT_EMAIL_SUBJECT_PREFIX
SUPPORT_RATE_LIMIT_MAX=$SUPPORT_RATE_LIMIT_MAX
SUPPORT_RATE_LIMIT_WINDOW_MINUTES=$SUPPORT_RATE_LIMIT_WINDOW_MINUTES
AI_ENABLED=$AI_ENABLED
AI_PROVIDER=$AI_PROVIDER
GROQ_API_KEY=$GROQ_API_KEY
GROQ_BASE_URL=$GROQ_BASE_URL
GROQ_TIMEOUT_MS=$GROQ_TIMEOUT_MS
GROQ_REASONING_EFFORT=$GROQ_REASONING_EFFORT
GROQ_MODEL=$GROQ_MODEL
GROQ_MODEL_CHAT=$GROQ_MODEL_CHAT
GROQ_MODEL_FAST=$GROQ_MODEL_FAST
TTS_ENABLED=$TTS_ENABLED
TTS_PROVIDER=$TTS_PROVIDER
AZURE_SPEECH_KEY=$AZURE_SPEECH_KEY
AZURE_SPEECH_REGION=$AZURE_SPEECH_REGION
AZURE_SPEECH_ENDPOINT=$AZURE_SPEECH_ENDPOINT
AZURE_SPEECH_TTS_URL=$AZURE_SPEECH_TTS_URL
AZURE_SPEECH_VOICES_URL=$AZURE_SPEECH_VOICES_URL
AZURE_SPEECH_VOICE=$AZURE_SPEECH_VOICE
TTS_FORMAT=$TTS_FORMAT
TTS_SPEED=$TTS_SPEED
TTS_TIMEOUT_MS=$TTS_TIMEOUT_MS
TTS_MAX_CHARS=$TTS_MAX_CHARS
FIREBASE_ENABLED=$FIREBASE_ENABLED
FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID
FIREBASE_CLIENT_EMAIL=$FIREBASE_CLIENT_EMAIL
FIREBASE_PRIVATE_KEY_BASE64=$FIREBASE_PRIVATE_KEY_BASE64
PUSH_SCHEDULER_ENABLED=$PUSH_SCHEDULER_ENABLED
PUSH_SCHEDULER_INTERVAL_MS=$PUSH_SCHEDULER_INTERVAL_MS
PUSH_DUE_REMINDER_DAYS=$PUSH_DUE_REMINDER_DAYS
PUSH_DEFAULT_TIMEZONE=$PUSH_DEFAULT_TIMEZONE
PUSH_EMAIL_APP_URL=$PUSH_EMAIL_APP_URL
FIREBASE_MESSAGING_SENDER_ID=$FIREBASE_MESSAGING_SENDER_ID
FIREBASE_WEB_APP_ID=$FIREBASE_WEB_APP_ID
FIREBASE_STORAGE_BUCKET=$FIREBASE_STORAGE_BUCKET
FIREBASE_WEB_AUTH_DOMAIN=$FIREBASE_WEB_AUTH_DOMAIN
FIREBASE_WEB_API_KEY=$FIREBASE_WEB_API_KEY
FIREBASE_VAPID_KEY=$FIREBASE_VAPID_KEY
EOF

# Mantem configuracoes adicionais trazidas pelo .env do projeto mesmo quando
# elas nao fazem parte da lista gerenciada acima (ex.: LOG_LEVEL).
# Para chaves gerenciadas, os valores normalizados deste script prevalecem.
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  case "$line" in *=*) ;; *) continue ;; esac
  key=${line%%=*}
  if ! printf %s "$key" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
    continue
  fi
  if ! grep -q -E "^${key}=" "$ENV_FILE"; then
    printf '%s\n' "$line" >> "$ENV_FILE"
  fi
done < "$previous_env_tmp"
rm -f "$previous_env_tmp"
chmod 600 "$ENV_FILE"

# Sobras de versoes antigas do deploy, que geravam esses arquivos no servidor.
rm -f docker-compose.server.yml app/Dockerfile.deploy

# Fixa o nome do projeto para que o volume do MySQL (hopecash_hopecash_mysql)
# seja reaproveitado independentemente do diretorio de checkout.
export COMPOSE_PROJECT_NAME=hopecash
COMPOSE=(docker compose --env-file "$ENV_FILE")
for compose_file in $COMPOSE_FILES; do
  if [ ! -f "$compose_file" ]; then
    echo "Arquivo Compose não encontrado: $compose_file" >&2
    exit 1
  fi
  COMPOSE+=(-f "$compose_file")
done

"${COMPOSE[@]}" config --quiet

echo "Portas selecionadas: web=$WEB_PORT api=$API_PORT mysql=$MYSQL_PORT retaguarda=$RETAGUARDA_PORT"

if [ "$RESET_DB" = "1" ]; then
  # Remove exclusivamente o banco e seu volume. Os volumes do Nginx Proxy
  # Manager guardam hosts/certificados e nunca podem ser atingidos por reset.
  echo "ATENCAO: removendo somente o MySQL e o volume hopecash_mysql"
  "${COMPOSE[@]}" stop api mysql || true
  "${COMPOSE[@]}" rm -f api mysql || true
  docker volume rm "${COMPOSE_PROJECT_NAME}_hopecash_mysql" >/dev/null 2>&1 || true
else
  # Deploy normal: nao derruba nada aqui. Containers de um deploy antigo sob
  # outro nome de projeto compose colidiriam com os container_name fixos ao
  # subir; o mysql fica sempre de fora dessa limpeza (nunca e recriado sem
  # necessidade, preservando conexoes ativas e o estado do banco).
  for container in hopecash-api hopecash-web hopecash-retaguarda; do
    if docker container inspect "$container" >/dev/null 2>&1; then
      owner="$(docker container inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$container" 2>/dev/null || true)"
      if [ "$owner" != "hopecash" ]; then
        echo "Removendo container orfao (projeto divergente): $container"
        docker rm -f "$container" >/dev/null 2>&1 || true
      fi
    fi
  done
fi

backup_database() {
  if ! docker container inspect hopecash-mysql >/dev/null 2>&1 \
    || [ "$(docker inspect -f '{{.State.Running}}' hopecash-mysql 2>/dev/null)" != "true" ]; then
    echo "MySQL ainda não existe; backup pré-deploy dispensado."
    return 0
  fi

  mkdir -p "$DEPLOY_BACKUP_DIR"
  chmod 700 "$DEPLOY_BACKUP_DIR"
  local stamp backup_path
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_path="$DEPLOY_BACKUP_DIR/pre-deploy-${stamp}-${BUILD_REF}.sql.gz"
  echo "Criando backup transacional em $backup_path"
  docker exec -e "MYSQL_PWD=$MYSQL_PASSWORD" hopecash-mysql \
    mysqldump --user="$MYSQL_USER" --single-transaction --quick --no-tablespaces \
      --routines --events --triggers "$MYSQL_DATABASE" \
    | gzip -9 > "$backup_path"
  test -s "$backup_path"
  chmod 600 "$backup_path"
  sha256sum "$backup_path" > "$backup_path.sha256"
  chmod 600 "$backup_path.sha256"

  # Mantém os dez backups automáticos mais recentes.
  find "$DEPLOY_BACKUP_DIR" -maxdepth 1 -type f -name 'pre-deploy-*.sql.gz' \
    -printf '%T@ %p\n' | sort -nr | tail -n +11 | cut -d' ' -f2- \
    | while IFS= read -r old_backup; do
        [ -n "$old_backup" ] || continue
        rm -f -- "$old_backup" "$old_backup.sha256"
      done
}

container_image_id() {
  docker container inspect -f '{{.Image}}' "$1" 2>/dev/null || true
}

container_image_name() {
  docker container inspect -f '{{.Config.Image}}' "$1" 2>/dev/null || true
}

OLD_API_IMAGE_ID="$(container_image_id hopecash-api)"
OLD_API_IMAGE_NAME="$(container_image_name hopecash-api)"
OLD_WEB_IMAGE_ID="$(container_image_id hopecash-web)"
OLD_WEB_IMAGE_NAME="$(container_image_name hopecash-web)"
OLD_RETAGUARDA_IMAGE_ID="$(container_image_id hopecash-retaguarda)"
OLD_RETAGUARDA_IMAGE_NAME="$(container_image_name hopecash-retaguarda)"
ROLLBACK_ARMED=0

rollback_on_error() {
  local exit_code=$?
  trap - ERR
  if [ "$ROLLBACK_ARMED" = "1" ]; then
    echo "Deploy falhou após a troca; restaurando imagens anteriores..." >&2
    [ -z "$OLD_API_IMAGE_ID" ] || [ -z "$OLD_API_IMAGE_NAME" ] \
      || docker image tag "$OLD_API_IMAGE_ID" "$OLD_API_IMAGE_NAME"
    [ -z "$OLD_WEB_IMAGE_ID" ] || [ -z "$OLD_WEB_IMAGE_NAME" ] \
      || docker image tag "$OLD_WEB_IMAGE_ID" "$OLD_WEB_IMAGE_NAME"
    [ -z "$OLD_RETAGUARDA_IMAGE_ID" ] || [ -z "$OLD_RETAGUARDA_IMAGE_NAME" ] \
      || docker image tag "$OLD_RETAGUARDA_IMAGE_ID" "$OLD_RETAGUARDA_IMAGE_NAME"
    "${COMPOSE[@]}" up -d --force-recreate --no-deps api web retaguarda || true
    "${COMPOSE[@]}" ps || true
  fi
  exit "$exit_code"
}
trap rollback_on_error ERR

if [ "$RESET_DB" != "1" ]; then
  backup_database
fi

BUILD_ARGS=(build)
if [ "$PULL" = "1" ]; then BUILD_ARGS+=(--pull); fi
if [ "$NO_CACHE" = "1" ]; then BUILD_ARGS+=(--no-cache); fi
BUILD_ARGS+=(api web retaguarda)
echo "Construindo novas imagens (aplicacao atual segue no ar durante o build)..."
"${COMPOSE[@]}" "${BUILD_ARGS[@]}"

# Garante infraestrutura no ar sem forcar recriacao. Se já estiver com a mesma
# configuração, esses comandos são no-op.
"${COMPOSE[@]}" up -d --no-deps mysql proxy-manager

# So troca os containers da aplicacao depois que a imagem nova ja existe: o
# 'stop antigo + start novo' acontece por servico, minimizando o tempo fora do
# ar em vez de derrubar a stack inteira antes do build (como antes).
ROLLBACK_ARMED=1
"${COMPOSE[@]}" up -d --force-recreate --no-deps --remove-orphans api web retaguarda

echo "Aguardando saude da API e do Web..."
for i in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${API_PORT}/api/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [ "$i" = "60" ]; then
    echo "API nao respondeu no tempo esperado" >&2
    "${COMPOSE[@]}" ps
    docker logs --tail 80 hopecash-api || true
    exit 1
  fi
done

for path in / /sqlite3.wasm /drift_worker.js; do
  curl -fsS "http://127.0.0.1:${WEB_PORT}${path}" >/dev/null
done

# As paginas publicas precisam responder com o HTML proprio. Verificar apenas o
# status 200 nao basta porque o fallback da SPA tambem devolve 200 quando o
# arquivo estatico nao entrou na imagem.
curl -fsS "http://127.0.0.1:${WEB_PORT}/marketing/" \
  | grep -F '<body class="marketing-page">' >/dev/null
curl -fsS "http://127.0.0.1:${WEB_PORT}/suporte/" \
  | grep -F '<body class="support-page">' >/dev/null

# Retaguarda: valida que a SPA responde.
curl -fsS "http://127.0.0.1:${RETAGUARDA_PORT}/" >/dev/null

ROLLBACK_ARMED=0
trap - ERR

if [ "$PRUNE" = "1" ]; then
  docker image prune -f
fi

"${COMPOSE[@]}" ps
echo "DEPLOY_OK web_port=${WEB_PORT} api_port=${API_PORT} retaguarda_port=${RETAGUARDA_PORT}"
