<#
.SYNOPSIS
    Compila um APK release do HopeCash e instala/atualiza via ADB quando disponivel.

.DESCRIPTION
    Etapas:
      1. flutter pub get
      2. Codegen do Drift (build_runner)
      3. flutter build apk --release, com --dart-define de API_BASE_URL/APP_VERSION/BUILD_REF/BUILD_TIME
         (mesmo padrao usado no Dockerfile do build web)
      4. Quando houver um dispositivo ADB conectado e autorizado:
         - envia o APK para /sdcard/Download
         - instala ou atualiza o app com adb install -r
         (equivalente a "Este Computador\<aparelho>\Armazenamento interno\Download")

    Pre-requisitos no celular: depuracao USB habilitada e autorizada para este PC
    (Configuracoes > Opcoes do desenvolvedor > Depuracao USB).

.EXAMPLE
    .\scripts\build-apk.ps1                          # build + envia + instala/atualiza via ADB
    .\scripts\build-apk.ps1 -SkipInstall             # build + envia, sem instalar
    .\scripts\build-apk.ps1 -SkipSend                # so gera o APK, nao mexe no ADB
    .\scripts\build-apk.ps1 -SkipCodegen             # pula build_runner (banco/schema nao mudou)
    .\scripts\build-apk.ps1 -ApiBaseUrl http://10.1.4.82:3000   # aponta para outro backend
#>
param(
    [string]$ApiBaseUrl = 'https://hopecash-api.coagru.com.br',
    [switch]$SkipCodegen,
    [switch]$SkipSend,
    [switch]$SkipInstall,
    # Mantido para compatibilidade: instalar agora ja e o comportamento padrao.
    [switch]$Install,
    [string]$DeviceSerial
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$appDir = Join-Path $root 'app'
$sw = [System.Diagnostics.Stopwatch]::StartNew()

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host ""
    Write-Host ">>> $Name" -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    & $Action
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
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

function Find-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $localProps = Join-Path $appDir 'android\local.properties'
    if (Test-Path $localProps) {
        $line = Select-String -Path $localProps -Pattern '^sdk\.dir=(.+)$' | Select-Object -First 1
        if ($line) {
            $sdkDir = $line.Matches[0].Groups[1].Value.Trim() -replace '\\\\', '\'
            $candidate = Join-Path $sdkDir 'platform-tools\adb.exe'
            if (Test-Path $candidate) { return $candidate }
        }
    }

    if ($env:ANDROID_HOME) {
        $candidate = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
        if (Test-Path $candidate) { return $candidate }
    }

    return $null
}

Write-Host "HopeCash - build APK" -ForegroundColor Green
Write-Host "Raiz: $root"
Write-Host "API_BASE_URL: $ApiBaseUrl"

Invoke-Step 'Pre-requisitos' {
    Assert-Command flutter
    Assert-Command dart
}

# ---------------------------------------------------------------- 1. Dependencias + codegen
Set-Location $appDir

Invoke-Step 'App: dependencias (flutter pub get)' { flutter pub get }

if (-not $SkipCodegen) {
    Invoke-Step 'App: codegen Drift (build_runner)' {
        dart run build_runner build --delete-conflicting-outputs
    }
}

# ---------------------------------------------------------------- 2. Build APK
$pubspecVersionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$' | Select-Object -First 1
$fullVersion = $pubspecVersionLine.Matches[0].Groups[1].Value.Trim()
$appVersion = ($fullVersion -split '\+')[0]

$buildRef = 'local'
try {
    $gitRef = (git -C $root rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $gitRef) { $buildRef = $gitRef.Trim() }
} catch {}

$buildTime = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-Host "Versao: $appVersion  Ref: $buildRef  Build: $buildTime"

Invoke-Step 'App: build APK release' {
    flutter build apk --release `
        --dart-define=API_BASE_URL=$ApiBaseUrl `
        --dart-define=APP_VERSION=$appVersion `
        --dart-define=BUILD_REF=$buildRef `
        --dart-define=BUILD_TIME=$buildTime
}

$apkPath = Join-Path $appDir 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apkPath)) {
    Write-Host "FALHOU: APK nao encontrado em $apkPath" -ForegroundColor Red
    exit 1
}

$apkName = "hopecash-$appVersion-$buildRef.apk"
$apkSizeMb = [Math]::Round((Get-Item $apkPath).Length / 1MB, 1)
Write-Host ""
Write-Host "APK gerado: $apkPath ($apkSizeMb MB)" -ForegroundColor Green

if ($SkipSend) {
    Set-Location $root
    Write-Host ""
    Write-Host "Envio ao celular pulado (-SkipSend)." -ForegroundColor Yellow
    exit 0
}

if ($SkipInstall -and $Install) {
    Write-Host "FALHOU: use somente -SkipInstall ou -Install, nao ambos." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- 3. Envio via ADB
$adb = Find-Adb
if (-not $adb) {
    Write-Host ""
    Write-Host "ADB nao encontrado; instalacao automatica ignorada." -ForegroundColor Yellow
    Write-Host "O APK ja esta pronto em: $apkPath" -ForegroundColor Yellow
    Set-Location $root
    exit 0
}

$adbArgs = @()
if ($DeviceSerial) { $adbArgs += @('-s', $DeviceSerial) }

Write-Host ""
Write-Host ">>> Verificando dispositivo conectado" -ForegroundColor Cyan
$devicesOutput = & $adb @adbArgs devices | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne '' }

if (-not $devicesOutput) {
    Write-Host "Nenhum dispositivo encontrado pelo adb; instalacao automatica ignorada." -ForegroundColor Yellow
    Write-Host "Conecte o celular por USB e habilite 'Depuracao USB' em Opcoes do desenvolvedor." -ForegroundColor Yellow
    Write-Host "O APK ja esta pronto em: $apkPath" -ForegroundColor Yellow
    Set-Location $root
    exit 0
}

if ($DeviceSerial) {
    $escapedSerial = [Regex]::Escape($DeviceSerial)
    $selectedDevice = $devicesOutput | Where-Object { $_ -match "^${escapedSerial}\t" } | Select-Object -First 1
    if (-not $selectedDevice) {
        Write-Host "Dispositivo '$DeviceSerial' nao encontrado; instalacao automatica ignorada." -ForegroundColor Yellow
        Write-Host "O APK ja esta pronto em: $apkPath" -ForegroundColor Yellow
        Set-Location $root
        exit 0
    }
    if ($selectedDevice -notmatch '\tdevice$') {
        $deviceState = ($selectedDevice -split '\t', 2)[1]
        Write-Host "Dispositivo '$DeviceSerial' indisponivel (estado: $deviceState)." -ForegroundColor Yellow
        Write-Host "O APK ja esta pronto em: $apkPath" -ForegroundColor Yellow
        Set-Location $root
        exit 0
    }
    $readyDevices = @($selectedDevice)
} else {
    $readyDevices = @($devicesOutput | Where-Object { $_ -match '\tdevice$' })
}

$unauthorized = $devicesOutput | Where-Object { $_ -match '\tunauthorized$' }
if ($unauthorized -and -not $readyDevices) {
    Write-Host "Dispositivo conectado mas nao autorizado; instalacao automatica ignorada." -ForegroundColor Yellow
    Write-Host "Desbloqueie o celular e aceite o prompt 'Permitir depuracao USB?'." -ForegroundColor Yellow
    Write-Host "O APK ja esta pronto em: $apkPath" -ForegroundColor Yellow
    Set-Location $root
    exit 0
}
if (-not $readyDevices) {
    Write-Host "Nenhum dispositivo ADB pronto; instalacao automatica ignorada." -ForegroundColor Yellow
    Write-Host "O APK ja esta pronto em: $apkPath" -ForegroundColor Yellow
    Set-Location $root
    exit 0
}
if ($readyDevices.Count -gt 1 -and -not $DeviceSerial) {
    Write-Host "Mais de um dispositivo conectado. Use -DeviceSerial <serial>:" -ForegroundColor Red
    $readyDevices | ForEach-Object { Write-Host "  $_" }
    exit 1
}

$devicePath = "/sdcard/Download/$apkName"
Invoke-Step "ADB: enviar APK para $devicePath" {
    & $adb @adbArgs push $apkPath $devicePath
}

if (-not $SkipInstall) {
    Invoke-Step 'ADB: instalar ou atualizar app no dispositivo' {
        & $adb @adbArgs install -r $apkPath
    }
}

Set-Location $root
$sw.Stop()
Write-Host ""
Write-Host ("Concluido em {0:mm\:ss}." -f $sw.Elapsed) -ForegroundColor Green
Write-Host "  APK local     : $apkPath"
Write-Host "  APK no celular: Armazenamento interno/Download/$apkName"
if ($SkipInstall) {
    Write-Host "  Abra o Gerenciador de Arquivos no celular e toque no APK para instalar." -ForegroundColor Yellow
} else {
    Write-Host "  App instalado/atualizado via ADB." -ForegroundColor Green
}
