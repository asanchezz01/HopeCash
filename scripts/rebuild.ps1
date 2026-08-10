<#
.SYNOPSIS
    Rebuild completo do HopeCash e republicacao dos containers.

.DESCRIPTION
    Etapas:
      1. Valida pre-requisitos locais
      2. Backend : npm install + testes (Vitest)
      3. App     : pub get + codegen Drift + analyze + testes + flutter build web
      4. Docker  : down, rebuild das imagens api/web, up com force-recreate
      5. Saude   : valida API, app web e assets do SQLite WASM

    Por padrao o volume MySQL e preservado. Use -ResetDatabase somente quando
    quiser apagar e recriar o banco local Docker.

.EXAMPLE
    .\scripts\rebuild.ps1                # rebuild completo com testes
    .\scripts\rebuild.ps1 -SkipTests     # mais rápido: pula testes e analyze
    .\scripts\rebuild.ps1 -SkipBackend   # só app web
    .\scripts\rebuild.ps1 -SkipApp       # só backend
    .\scripts\rebuild.ps1 -NoCache -Pull # rebuild das imagens sem cache e puxando bases
    .\scripts\rebuild.ps1 -ResetDatabase # apaga o volume MySQL antes de republicar
#>
param(
    [switch]$SkipTests,
    [switch]$SkipBackend,
    [switch]$SkipApp,
    [switch]$NoCache,
    [switch]$Pull,
    [switch]$Prune,
    [switch]$ResetDatabase
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sw = [System.Diagnostics.Stopwatch]::StartNew()

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host ""
    Write-Host ">>> $Name" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FALHOU: $Name (exit $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}

function Assert-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Host "FALHOU: comando '$Name' nao encontrado no PATH." -ForegroundColor Red
        exit 1
    }
}

function Invoke-DockerCompose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & docker compose @Args
}

Write-Host "HopeCash rebuild/redeploy" -ForegroundColor Green
Write-Host "Raiz: $root"

Invoke-Step 'Pre-requisitos' {
    Assert-Command docker
    if (-not $SkipBackend) {
        Assert-Command npm
    }
    if (-not $SkipApp) {
        Assert-Command flutter
        Assert-Command dart
    }
    Invoke-DockerCompose version | Out-Host
}

# ---------------------------------------------------------------- 1. Backend
if (-not $SkipBackend) {
    Set-Location "$root\backend"

    Invoke-Step 'Backend: dependencias (npm install)' { npm install --no-audit --no-fund }

    if (-not $SkipTests) {
        Invoke-Step 'Backend: testes (Vitest)' { npm test }
    }
}

# ---------------------------------------------------------------- 2. App Flutter
if (-not $SkipApp) {
    Set-Location "$root\app"

    Invoke-Step 'App: dependencias (flutter pub get)' { flutter pub get }

    Invoke-Step 'App: codegen Drift (build_runner)' {
        dart run build_runner build --delete-conflicting-outputs
    }

    if (-not $SkipTests) {
        Invoke-Step 'App: analise estatica (flutter analyze)' { flutter analyze }
        Invoke-Step 'App: testes (flutter test)' { flutter test }
    }

    Invoke-Step 'App: build web release' { flutter build web --release }

    # O build incremental do Flutter nem sempre copia arquivos novos de web/;
    # o SQLite WASM e o worker do Drift sao obrigatorios para o banco local no navegador.
    foreach ($asset in 'sqlite3.wasm', 'drift_worker.js') {
        if (-not (Test-Path "build\web\$asset")) {
            Copy-Item "web\$asset" "build\web\$asset"
            Write-Host "    copiado manualmente: $asset" -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------- 3. Docker
Set-Location $root

$services = @()
if (-not $SkipBackend) { $services += 'api' }
if (-not $SkipApp)     { $services += 'web' }

if ($services.Count -gt 0) {
    $downArgs = @('down', '--remove-orphans')
    if ($ResetDatabase) {
        $downArgs += '--volumes'
        Write-Host ""
        Write-Host "ATENCAO: -ResetDatabase apagara o volume Docker do MySQL." -ForegroundColor Yellow
    }

    Invoke-Step 'Docker: parar containers antigos' {
        Invoke-DockerCompose @downArgs
    }

    if ($Pull) {
        Invoke-Step 'Docker: atualizar imagens base' {
            Invoke-DockerCompose pull mysql
        }
    }

    $buildArgs = @('build')
    if ($Pull) {
        $buildArgs += '--pull'
    }
    if ($NoCache) {
        $buildArgs += '--no-cache'
    }
    $buildArgs += $services

    Invoke-Step "Docker: rebuild das imagens ($($services -join ', '))" {
        Invoke-DockerCompose @buildArgs
    }

    # Argumentos como array de strings: tokens iniciados por '-' passados
    # inline seriam interpretados como parametros do wrapper e o '-d' se
    # perderia, deixando o compose anexado (o script nunca terminaria).
    $upArgs = @('up', '-d', '--force-recreate', '--remove-orphans') + $services
    Invoke-Step 'Docker: republicar containers' {
        Invoke-DockerCompose @upArgs
    }

    if ($Prune) {
        Invoke-Step 'Docker: limpar imagens sem uso' {
            docker image prune -f
        }
    }
}

# ---------------------------------------------------------------- 4. Saúde
Write-Host ""
Write-Host '>>> Verificacao de saude' -ForegroundColor Cyan

function Wait-Healthy {
    param([string]$Name, [string]$Url, [int]$TimeoutSec = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $res = Invoke-WebRequest $Url -UseBasicParsing -TimeoutSec 5
            if ($res.StatusCode -eq 200) {
                Write-Host "    OK  $Name ($Url)" -ForegroundColor Green
                return
            }
        } catch { Start-Sleep -Seconds 2 }
    }
    Write-Host "    FALHOU  $Name nao respondeu em ${TimeoutSec}s ($Url)" -ForegroundColor Red
    Write-Host "    Logs: docker logs hopecash-api / docker logs hopecash-web" -ForegroundColor Yellow
    exit 1
}

if (-not $SkipBackend -or -not $SkipApp) {
    Wait-Healthy 'API'     'http://localhost:3000/api/v1/health'
    Wait-Healthy 'Swagger' 'http://localhost:3000/api/docs/'
}

if (-not $SkipApp) {
    Wait-Healthy 'App Web'      'http://localhost:8080'
    Wait-Healthy 'SQLite WASM'  'http://localhost:8080/sqlite3.wasm'
    Wait-Healthy 'Drift worker' 'http://localhost:8080/drift_worker.js'
}

$sw.Stop()
Write-Host ""
Write-Host ("Rebuild + redeploy concluidos em {0:mm\:ss}." -f $sw.Elapsed) -ForegroundColor Green
Write-Host ""
Write-Host "  App Web : http://localhost:8080   (Ctrl+Shift+R na primeira vez - cache do service worker)"
Write-Host "  API     : http://localhost:3000"
Write-Host "  Swagger : http://localhost:3000/api/docs"
Write-Host "  Demo    : demo@hopecash.app / Demo123!"
