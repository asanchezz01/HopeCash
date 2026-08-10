<#
.SYNOPSIS
    Publica o HopeCash em um servidor Docker remoto via Git.

.DESCRIPTION
    Le o arquivo privado de credenciais, acessa o servidor por SSH, faz clone
    ou atualizacao do repositorio em REMOTE_DIR, mescla o backend/.env local
    no .env remoto, grava as portas livres e republica os containers com
    Docker Compose. Parametros explicitos da linha de comando continuam tendo
    prioridade sobre os valores do arquivo.

    O token Git e usado apenas como header temporario do comando git; ele nao
    e gravado no remote origin.

.EXAMPLE
    .\scripts\deploy-server.ps1
    .\scripts\deploy-server.ps1 -NoCache -Pull
    .\scripts\deploy-server.ps1 -WebPort 8092 -ApiPort 3001 -MysqlPort 3306
    .\scripts\deploy-server.ps1 -ResetDatabase
#>
param(
    [string]$CredentialFile = 'C:\app\hopecash_private\deploy_credencial.txt',
    [string]$ProjectEnvFile,
    [string]$GitRepo,
    [string]$Branch,
    [int]$WebPort,
    [int]$ApiPort,
    [int]$MysqlPort,
    [string]$ApiBaseUrl,
    [string]$CorsAllowedOrigins,
    [switch]$NoCache,
    [switch]$Pull,
    [switch]$Prune,
    [switch]$ResetDatabase
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function Read-DeployConfig {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Arquivo de credenciais nao encontrado: $Path"
    }

    $config = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
        $idx = $trimmed.IndexOf('=')
        if ($idx -le 0) { continue }
        $key = $trimmed.Substring(0, $idx).Trim()
        $value = $trimmed.Substring($idx + 1).Trim()
        $config[$key] = $value
    }
    return $config
}

function Require-Config {
    param($Config, [string]$Key)
    if (-not $Config.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Config[$Key])) {
        throw "Chave obrigatoria ausente no arquivo de credenciais: $Key"
    }
    return $Config[$Key]
}

function Quote-Bash {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return "''" }
    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Invoke-Remote {
    param(
        [string]$Target,
        [string]$Command,
        [int]$TimeoutSec = 600
    )
    & ssh -o BatchMode=yes -o ConnectTimeout=10 $Target $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Comando remoto falhou com exit $LASTEXITCODE"
    }
}

$config = Read-DeployConfig $CredentialFile
$projectEnvPath = if ($ProjectEnvFile) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProjectEnvFile)
} else {
    Join-Path $root 'backend\.env'
}
$projectEnvBase64 = ''
if (Test-Path -LiteralPath $projectEnvPath) {
    $projectEnvContent = Get-Content -LiteralPath $projectEnvPath -Raw
    $projectEnvContent = $projectEnvContent -replace "`r`n", "`n" -replace "`r", "`n"
    $projectEnvBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($projectEnvContent))
    Write-Host "Configuracao local: $projectEnvPath" -ForegroundColor Green
} else {
    Write-Host "Configuracao local nao encontrada; mantendo somente o .env remoto: $projectEnvPath" -ForegroundColor Yellow
}

$server = Require-Config $config 'SERVER'
$sshUser = Require-Config $config 'SSH_USER'
$remoteDir = $config['REMOTE_DIR']
if ([string]::IsNullOrWhiteSpace($remoteDir)) { $remoteDir = '/opt/hopecash' }

$branchValue = if ($Branch) { $Branch } elseif ($config['BRANCH']) { $config['BRANCH'] } else { 'main' }
$gitUser = $config['GIT_USERNAME']
$gitToken = $config['GIT_TOKEN']
$repoValue = if ($GitRepo) { $GitRepo } elseif ($config['GIT_REPO']) { $config['GIT_REPO'] } else { "https://github.com/$gitUser/HopeCash.git" }

if ([string]::IsNullOrWhiteSpace($repoValue)) {
    throw 'Informe GIT_REPO no arquivo de credenciais ou passe -GitRepo.'
}
if ([string]::IsNullOrWhiteSpace($gitUser) -or [string]::IsNullOrWhiteSpace($gitToken)) {
    throw 'GIT_USERNAME e GIT_TOKEN sao obrigatorios para clone/pull privado.'
}

$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${gitUser}:$gitToken"))
$authHeader = "AUTHORIZATION: basic $basic"

$branchCheck = & git -c http.extraheader="$authHeader" ls-remote --heads $repoValue $branchValue
if ($LASTEXITCODE -ne 0) {
    throw 'Nao foi possivel validar o repositorio Git com as credenciais informadas.'
}
if ([string]::IsNullOrWhiteSpace($branchCheck)) {
    $mainCheck = & git -c http.extraheader="$authHeader" ls-remote --heads $repoValue main
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($mainCheck)) {
        Write-Host "Branch '$branchValue' nao encontrada; usando 'main'." -ForegroundColor Yellow
        $branchValue = 'main'
    } else {
        throw "Branch '$branchValue' nao encontrada no repositorio."
    }
}

$target = "$sshUser@$server"

Write-Host "HopeCash deploy remoto" -ForegroundColor Green
Write-Host "Servidor : $server"
Write-Host "Usuario  : $sshUser"
Write-Host "Pasta    : $remoteDir"
Write-Host "Branch   : $branchValue"

Write-Host ""
Write-Host ">>> Testando SSH" -ForegroundColor Cyan
Invoke-Remote -Target $target -Command 'whoami >/dev/null && docker compose version >/dev/null'

$webOverride = if ($WebPort -gt 0) { "$WebPort" } else { '' }
$apiOverride = if ($ApiPort -gt 0) { "$ApiPort" } else { '' }
$mysqlOverride = if ($MysqlPort -gt 0) { "$MysqlPort" } else { '' }
$apiBaseUrlValue = if ($ApiBaseUrl) { $ApiBaseUrl } elseif ($config['API_BASE_URL']) { $config['API_BASE_URL'] } else { 'https://hopecash-api.coagru.com.br' }
$corsOriginsValue = if ($CorsAllowedOrigins) {
    $CorsAllowedOrigins
} elseif ($config['CORS_ALLOWED_ORIGINS']) {
    $config['CORS_ALLOWED_ORIGINS']
} else {
    'https://hopecash.coagru.com.br,https://hopecash-api.coagru.com.br,http://10.1.4.82:8092'
}
$noCacheFlag = if ($NoCache) { '1' } else { '0' }
$pullFlag = if ($Pull) { '1' } else { '0' }
$pruneFlag = if ($Prune) { '1' } else { '0' }
$resetFlag = if ($ResetDatabase) { '1' } else { '0' }

$remotePreamble = @"
set -euo pipefail

REMOTE_DIR=$(Quote-Bash $remoteDir)
REPO_URL=$(Quote-Bash $repoValue)
BRANCH=$(Quote-Bash $branchValue)
AUTH_HEADER=$(Quote-Bash $authHeader)
WEB_PORT_OVERRIDE=$(Quote-Bash $webOverride)
API_PORT_OVERRIDE=$(Quote-Bash $apiOverride)
MYSQL_PORT_OVERRIDE=$(Quote-Bash $mysqlOverride)
API_BASE_URL_VALUE=$(Quote-Bash $apiBaseUrlValue)
CORS_ALLOWED_ORIGINS_VALUE=$(Quote-Bash $corsOriginsValue)
NO_CACHE=$noCacheFlag
PULL=$pullFlag
PRUNE=$pruneFlag
RESET_DB=$resetFlag
PROJECT_ENV_BASE64=$(Quote-Bash $projectEnvBase64)

"@

$remoteBody = @'
mkdir -p "$(dirname "$REMOTE_DIR")"

if [ -d "$REMOTE_DIR/.git" ]; then
  echo "Atualizando repositorio em $REMOTE_DIR"
  git -C "$REMOTE_DIR" -c http.extraheader="$AUTH_HEADER" fetch --prune origin "$BRANCH"
  git -C "$REMOTE_DIR" checkout "$BRANCH"
  git -C "$REMOTE_DIR" reset --hard "origin/$BRANCH"
elif [ -z "$(find "$REMOTE_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
  echo "Clonando repositorio em $REMOTE_DIR"
  git -c http.extraheader="$AUTH_HEADER" clone --branch "$BRANCH" "$REPO_URL" "$REMOTE_DIR"
else
  echo "ERRO: $REMOTE_DIR existe, nao esta vazio e nao e um repositorio git." >&2
  exit 1
fi

cd "$REMOTE_DIR"

# Mescla o .env do projeto no arquivo persistente do servidor sem executar o
# conteudo. Chaves locais substituem as de mesmo nome; chaves exclusivamente
# remotas (portas, segredos gerados etc.) permanecem intactas.
ENV_FILE="$REMOTE_DIR/.env"
if [ -n "$PROJECT_ENV_BASE64" ]; then
  project_env_tmp="$(mktemp)"
  merged_env_tmp="$(mktemp)"
  printf %s "$PROJECT_ENV_BASE64" | base64 -d > "$project_env_tmp"

  if [ -f "$ENV_FILE" ]; then
    cp "$ENV_FILE" "$merged_env_tmp"
  else
    : > "$merged_env_tmp"
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    key=${line%%=*}
    if ! printf %s "$key" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
      continue
    fi
    next_env_tmp="$(mktemp)"
    grep -v -E "^${key}=" "$merged_env_tmp" > "$next_env_tmp" || true
    mv "$next_env_tmp" "$merged_env_tmp"
    printf '%s\n' "$line" >> "$merged_env_tmp"
  done < "$project_env_tmp"

  mv "$merged_env_tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  rm -f "$project_env_tmp"
  echo "Configuracao do projeto aplicada ao .env remoto."
fi

ENV_FILE="$REMOTE_DIR/.env" \
WEB_PORT="$WEB_PORT_OVERRIDE" \
API_PORT="$API_PORT_OVERRIDE" \
MYSQL_PORT="$MYSQL_PORT_OVERRIDE" \
API_BASE_URL="$API_BASE_URL_VALUE" \
CORS_ALLOWED_ORIGINS="$CORS_ALLOWED_ORIGINS_VALUE" \
NO_CACHE="$NO_CACHE" \
PULL="$PULL" \
PRUNE="$PRUNE" \
RESET_DB="$RESET_DB" \
bash scripts/deploy.sh
'@

$remoteScript = ($remotePreamble + $remoteBody) -replace "`r`n", "`n" -replace "`r", "`n"

Write-Host ""
Write-Host ">>> Publicando no servidor" -ForegroundColor Cyan
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript))
Invoke-Remote -Target $target -Command "printf %s $(Quote-Bash $encoded) | base64 -d | bash" -TimeoutSec 1800

Write-Host ""
Write-Host "Deploy remoto concluido." -ForegroundColor Green
