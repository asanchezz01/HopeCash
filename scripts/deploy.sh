#!/usr/bin/env bash
# Publica o HopeCash com Docker Compose a partir de um checkout do repositorio.
# Roda no servidor de producao — pelo runner self-hosted do GitHub Actions
# (.github/workflows/deploy.yml) ou via SSH (scripts/deploy-server.ps1).
#
# Entradas (variaveis de ambiente, todas opcionais):
#   ENV_FILE                        .env persistente (padrao /opt/hopecash/.env)
#   WEB_PORT / API_PORT / MYSQL_PORT  forcam portas; senao usa o .env ou a primeira livre
#   API_BASE_URL / CORS_ALLOWED_ORIGINS
#   NO_CACHE=1  PULL=1  PRUNE=1  RESET_DB=1
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-/opt/hopecash/.env}"
NO_CACHE="${NO_CACHE:-0}"
PULL="${PULL:-0}"
PRUNE="${PRUNE:-0}"
RESET_DB="${RESET_DB:-0}"

# Guarda as entradas antes de carregar o .env, que usa os mesmos nomes.
WEB_PORT_IN="${WEB_PORT:-}"
API_PORT_IN="${API_PORT:-}"
MYSQL_PORT_IN="${MYSQL_PORT:-}"
RETAGUARDA_PORT_IN="${RETAGUARDA_PORT:-}"
API_BASE_URL_IN="${API_BASE_URL:-}"
CORS_IN="${CORS_ALLOWED_ORIGINS:-}"

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

API_BASE_URL="${API_BASE_URL_IN:-${API_BASE_URL:-https://hopecash-api.coagru.com.br}}"
CORS_ALLOWED_ORIGINS="${CORS_IN:-${CORS_ALLOWED_ORIGINS:-https://hopecash.coagru.com.br,https://hopecash-api.coagru.com.br,https://hopecash-retaguarda.coagru.com.br,http://10.1.4.82:8092,http://10.1.4.82:${RETAGUARDA_PORT}}}"

# Garante que a origem web da retaguarda (porta dinamica) esteja no CORS, mesmo
# quando um CORS_ALLOWED_ORIGINS pre-existente foi herdado do .env do servidor.
ensure_origin() {
  local origin="$1"
  case ",$CORS_ALLOWED_ORIGINS," in
    *",$origin,"*) ;;
    *) CORS_ALLOWED_ORIGINS="${CORS_ALLOWED_ORIGINS:+$CORS_ALLOWED_ORIGINS,}$origin" ;;
  esac
}
ensure_origin "http://10.1.4.82:${RETAGUARDA_PORT}"
ensure_origin "https://hopecash-retaguarda.coagru.com.br"

# Metadados de versao/build — permitem confirmar, no rodape do dashboard, qual
# commit esta efetivamente publicado em cada container. Recalculados a cada deploy.
BUILD_REF="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

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
# elas nao fazem parte da lista gerenciada acima (ex.: LOG_LEVEL/OLLAMA_*).
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
COMPOSE=(docker compose --env-file "$ENV_FILE" -f docker-compose.yml)

echo "Portas selecionadas: web=$WEB_PORT api=$API_PORT mysql=$MYSQL_PORT retaguarda=$RETAGUARDA_PORT"

if [ "$RESET_DB" = "1" ]; then
  # Reset explicito do banco: aqui a parada é intencional, entao derruba tudo
  # (inclusive o mysql) e recomeca do zero.
  echo "ATENCAO: removendo containers e volumes do projeto HopeCash (mysql sera recriado)"
  "${COMPOSE[@]}" down --remove-orphans --volumes || true

  for container in hopecash-mysql hopecash-api hopecash-web hopecash-retaguarda; do
    if docker container inspect "$container" >/dev/null 2>&1; then
      echo "Removendo container antigo: $container"
      docker rm -f "$container" >/dev/null 2>&1 || true
    fi
  done

  # A rede default pode sobrar (ex.: o down nao a removeu por causa de um
  # container preso a ela). Remove-la evita o conflito "network with name
  # hopecash_default already exists" no 'up' seguinte.
  if docker network inspect hopecash_default >/dev/null 2>&1; then
    echo "Removendo rede antiga: hopecash_default"
    docker network rm hopecash_default >/dev/null 2>&1 || true
  fi
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

BUILD_ARGS=(build)
if [ "$PULL" = "1" ]; then BUILD_ARGS+=(--pull); fi
if [ "$NO_CACHE" = "1" ]; then BUILD_ARGS+=(--no-cache); fi
BUILD_ARGS+=(api web retaguarda)
echo "Construindo novas imagens (aplicacao atual segue no ar durante o build)..."
"${COMPOSE[@]}" "${BUILD_ARGS[@]}"

# Garante o mysql no ar sem forcar recriacao: se ja estiver rodando com a
# mesma config, isso e um no-op (sem restart, sem downtime do banco).
"${COMPOSE[@]}" up -d --no-deps mysql

# So troca os containers da aplicacao depois que a imagem nova ja existe: o
# 'stop antigo + start novo' acontece por servico, minimizando o tempo fora do
# ar em vez de derrubar a stack inteira antes do build (como antes).
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

# Retaguarda: valida que a SPA responde.
curl -fsS "http://127.0.0.1:${RETAGUARDA_PORT}/" >/dev/null

if [ "$PRUNE" = "1" ]; then
  docker image prune -f
fi

"${COMPOSE[@]}" ps
echo "DEPLOY_OK web_port=${WEB_PORT} api_port=${API_PORT} retaguarda_port=${RETAGUARDA_PORT}"
