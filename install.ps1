# ─────────────────────────────────────────────────────────────
# GASAK ENGINE TOOLCHAIN — WINDOWS INSTALLER v1.0
# Target Environment: Windows 10/11 (PowerShell 5.1+)
# Run as: powershell -ExecutionPolicy Bypass -File install.ps1
# ─────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

# ─── CONFIGURATION ────────────────────────────────────────────
$SERVER_IP        = "10.70.0.110"
$SERVER_PORT      = "9001"
$VAULT_PORT       = "9002"
$GASAK_DIST_TOKEN = "gsk_dist_9f2k7x"
$BASE_URL         = "http://${SERVER_IP}:${SERVER_PORT}"
$VAULT_URL        = "http://${SERVER_IP}:${VAULT_PORT}"

$REAL_USER   = $env:USERNAME
$REAL_HOME   = $env:USERPROFILE
$INSTALL_DIR = "$REAL_HOME\gasak-dist"
$CONFIG_DIR  = "$REAL_HOME\.config\gasak"
$ENV_PATH    = "$INSTALL_DIR\.env"
$AGENT_DIR   = "$REAL_HOME\gasak-agent"

$DEVICE_HOST = $env:COMPUTERNAME

$CURL_TIMEOUT_CONNECT = 30
$CURL_TIMEOUT_MAX     = 300
$CURL_TIMEOUT_BINARY  = 600

# ─── COLORS ──────────────────────────────────────────────────
function ok($msg)   { Write-Host "   [+] $msg" -ForegroundColor Green }
function err($msg)  { Write-Host "   [x] $msg" -ForegroundColor Red }
function warn($msg) { Write-Host "   [!] $msg" -ForegroundColor Yellow }
function info($msg) { Write-Host "   --> $msg" -ForegroundColor Cyan }
function step($msg) { Write-Host "`n$msg" -ForegroundColor Cyan }

## ─── HEADER ──────────────────────────────────────────────────
#Clear-Host
#Write-Host ""
#Write-Host "  ██████╗  █████╗ ███████╗ █████╗ ██╗  ██╗" -ForegroundColor Magenta
#Write-Host "  ██╔════╝ ██╔══██╗██╔════╝██╔══██╗██║ ██╔╝" -ForegroundColor Magenta
#Write-Host "  ██║   ███╗███████║███████╗███████║█████╔╝ " -ForegroundColor Magenta
#Write-Host "  ██║   ██║██╔══██║╚════██║██╔══██║██╔═██╗ " -ForegroundColor Magenta
#Write-Host "  ╚██████╔╝██║  ██║███████║██║  ██║██║  ██╗" -ForegroundColor Magenta
#Write-Host "   ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝" -ForegroundColor Magenta
#Write-Host ""
#Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor White
#Write-Host "  ║  GASAK SYSTEM TOOLCHAIN INSTALLER  v1.0 (Windows)        ║" -ForegroundColor White
#Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor White
#Write-Host ""
#
## ─── STEP 1: PREFLIGHT ───────────────────────────────────────
step "  ┌─ STEP 1/5: System Compatibility Check"

# PowerShell version check
$psVer = $PSVersionTable.PSVersion.Major
if ($psVer -lt 5) {
    err "PowerShell 5.1+ dibutuhkan. Versi lo: $psVer"
    exit 1
}
ok "PowerShell: v$($PSVersionTable.PSVersion)"

# Network check
info "Checking network connectivity..."
try {
    $null = Invoke-WebRequest -Uri "$BASE_URL" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
    ok "Network: Connected ke ${SERVER_IP}:${SERVER_PORT}"
} catch {
    err "Network: Ga bisa reach ${SERVER_IP}:${SERVER_PORT}"
    err "Pastiin ZeroTier lo nyala dan terhubung ke network Parkee"
    exit 1
}

# Disk space check (in MB)
$disk = Get-PSDrive -Name ($REAL_HOME[0]) | Select-Object -ExpandProperty Free
$diskMB = [math]::Round($disk / 1MB)
if ($diskMB -gt 100) {
    ok "Disk: ${diskMB}MB available"
} else {
    warn "Disk: Low space (${diskMB}MB)"
}

# Create directories
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $CONFIG_DIR  | Out-Null
New-Item -ItemType Directory -Force -Path $AGENT_DIR   | Out-Null
ok "Workspace ready"

Write-Host "  └─"

# ─── STEP 2: CHECK PYTHON ────────────────────────────────────
step "  ┌─ STEP 2/5: Dependency Check"

# Python check
info "Checking Python..."
$pythonCmd = $null
foreach ($cmd in @("python", "python3", "py")) {
    try {
        $ver = & $cmd --version 2>&1
        if ($ver -match "Python 3") {
            $pythonCmd = $cmd
            ok "Python: $ver"
            break
        }
    } catch { }
}

if (-not $pythonCmd) {
    err "Python 3 tidak ditemukan!"
    warn "Download dari: https://www.python.org/downloads/"
    warn "Pastiin centang 'Add Python to PATH' waktu install"
    exit 1
}

# pip check
info "Checking pip..."
try {
    $null = & $pythonCmd -m pip --version 2>&1
    ok "pip: OK"
} catch {
    err "pip tidak ditemukan, coba: $pythonCmd -m ensurepip"
    exit 1
}

# ssh-keygen check (built-in di Windows 10+)
info "Checking ssh-keygen..."
if (Get-Command ssh-keygen -ErrorAction SilentlyContinue) {
    ok "ssh-keygen: OK"
} else {
    err "ssh-keygen tidak ditemukan"
    warn "Enable OpenSSH Client di: Settings > Apps > Optional Features > OpenSSH Client"
    exit 1
}

# openssl check
info "Checking openssl..."
if (Get-Command openssl -ErrorAction SilentlyContinue) {
    ok "openssl: OK"
} else {
    warn "openssl tidak ditemukan — akan pakai PowerShell fallback untuk key conversion"
}

Write-Host "  └─"

# ─── STEP 3: PYTHON PACKAGES ─────────────────────────────────
step "  ┌─ STEP 3/5: Python Environment Setup"

$PYTHON_PKGS = @(
    "requests",
    "python-dotenv",
    "rich",
    "questionary",
    "paramiko",
    "iterfzf"
)

$pkgTotal = $PYTHON_PKGS.Count
$pkgIdx   = 0

foreach ($pkg in $PYTHON_PKGS) {
    $pkgIdx++
    $importName = $pkg -replace "python-dotenv", "dotenv" -replace "-", "_"
    info "[$pkgIdx/$pkgTotal] $pkg..."

    $alreadyInstalled = & $pythonCmd -c "import $importName" 2>&1
    if ($LASTEXITCODE -eq 0) {
        ok "$pkg (cached)"
        continue
    }

    $result = & $pythonCmd -m pip install $pkg --quiet 2>&1
    if ($LASTEXITCODE -eq 0) {
        ok "$pkg installed"
    } else {
        warn "$pkg failed — $result"
    }
}

Write-Host "  └─"

# ─── STEP 4: DOWNLOAD COMPONENTS ─────────────────────────────
step "  ┌─ STEP 4/5: Downloading GASAK Components"

$COMPONENTS = @(
    @{ name = "gasak-windows-amd64.exe"; dest = $INSTALL_DIR; rename = "gasak.exe" },
    @{ name = "deploy_parkee_win.py";    dest = $INSTALL_DIR; rename = $null },
    @{ name = "settlement_rfs.py";       dest = $INSTALL_DIR; rename = $null },
    @{ name = "decode_and_merge.py";     dest = $INSTALL_DIR; rename = $null },
    @{ name = "log_cleaner.py";          dest = $INSTALL_DIR; rename = $null },
    @{ name = "server.properties";       dest = $AGENT_DIR;   rename = $null }
)

$compTotal  = $COMPONENTS.Count
$downloaded = 0
$failed     = 0

$headers = @{
    "X-Gasak-Host"    = $DEVICE_HOST
    "X-Gasak-Token"   = $GASAK_DIST_TOKEN
    "X-Gasak-Version" = "installing"
    "X-Gasak-User"    = $REAL_USER
}

foreach ($comp in $COMPONENTS) {
    $fname   = $comp.name
    $destDir = $comp.dest
    $rename  = $comp.rename

    $outName = if ($rename) { $rename } else { $fname }
    $outPath = "$destDir\$outName"

    $timeout = if ($fname -match "\.exe$") { $CURL_TIMEOUT_BINARY } else { $CURL_TIMEOUT_MAX }

    info "Fetching $fname..."
    try {
        Invoke-WebRequest `
            -Uri "$BASE_URL/$fname" `
            -OutFile $outPath `
            -Headers $headers `
            -TimeoutSec $timeout `
            -UseBasicParsing `
            -ErrorAction Stop

        $sizeMB = [math]::Round((Get-Item $outPath).Length / 1KB, 1)
        ok "$outName downloaded (${sizeMB}KB)"
        $downloaded++
    } catch {
        err "$fname failed: $($_.Exception.Message)"
        $failed++
    }
}

info "Downloaded: $downloaded/$compTotal components"
if ($failed -gt 0) {
    warn "Failed: $failed (bisa di-retry manual)"
}

Write-Host "  └─"

# ─── STEP 5: SECURITY & VAULT ────────────────────────────────
step "  ┌─ STEP 5/5: Security & Configuration"

# .env template
if (-not (Test-Path $ENV_PATH)) {
    info "Creating environment configuration..."
    @"
# GASAK ENVIRONMENT CONFIGURATION
# Generated by GASAK Installer v1.0 (Windows)

# URLs
GLPI_URL=
OUTLINE_URL=

# APIs
OUTLINE_API_KEY=
LINEAR_API_KEY=

# SSH Credentials
PARKEE_SSH_USER=support
PARKEE_SSH_PASS=

# Google Sheets
GSHEET_DEPLOY_ID=
GSHEET_DEPLOY_GID=

# CMS Database
CMS_DB_HOST=
CMS_DB_PORT=5432
CMS_DB_USER=
CMS_DB_PASS=
CMS_DB_NAME=
"@ | Set-Content -Path $ENV_PATH -Encoding UTF8
    ok "Environment template created"
} else {
    ok "Environment file exists (skipped)"
}

# RSA Keypair
$privKeyPath = "$CONFIG_DIR\id_rsa"
$pubKeyPath  = "$CONFIG_DIR\id_rsa.pub"
$vaultPath   = "$CONFIG_DIR\vault"

Remove-Item -Force -ErrorAction SilentlyContinue $privKeyPath, $pubKeyPath, $vaultPath

info "Generating RSA-2048 identity keypair..."
& ssh-keygen -t rsa -b 2048 -m PEM -f $privKeyPath -N '""' 2>&1 | Out-Null

if (-not (Test-Path $privKeyPath)) {
    err "Gagal generate keypair"
    exit 1
}

# Convert ke PKCS#8 public key format yang bisa dibaca Go (x509.ParsePKIXPublicKey)
if (Get-Command openssl -ErrorAction SilentlyContinue) {
    & openssl rsa -in $privKeyPath -pubout -out $pubKeyPath 2>&1 | Out-Null
    ok "RSA-2048 identity generated (openssl)"
} else {
    # Fallback: pakai PowerShell native untuk export public key
    warn "openssl tidak ada — pakai PowerShell fallback untuk public key export"
    try {
        Add-Type -AssemblyName System.Security
        $privPem    = Get-Content $privKeyPath -Raw
        $privBytes  = [Convert]::FromBase64String(
            ($privPem -replace "-----.*?-----" -replace "\s","")
        )
        $rsa        = [System.Security.Cryptography.RSA]::Create()
        $rsa.ImportRSAPrivateKey($privBytes, [ref]$null)
        $pubBytes   = $rsa.ExportSubjectPublicKeyInfo()
        $pubB64     = [Convert]::ToBase64String($pubBytes)
        $pubPem     = "-----BEGIN PUBLIC KEY-----`n$pubB64`n-----END PUBLIC KEY-----"
        Set-Content -Path $pubKeyPath -Value $pubPem -Encoding ASCII
        ok "RSA-2048 identity generated (PowerShell fallback)"
    } catch {
        err "Gagal export public key: $_"
        err "Install openssl dan re-run installer"
        exit 1
    }
}

# Register ke vault
info "Registering with central vault..."
if (Test-Path $pubKeyPath) {
    $pureKey = (Get-Content $pubKeyPath | Where-Object { $_ -notmatch "-----" }) -join ""
    $body    = "{`"token`":`"$GASAK_DIST_TOKEN`",`"public_key`":`"$pureKey`"}"

    try {
        $resp = Invoke-WebRequest `
            -Uri "$VAULT_URL/getenv" `
            -Method POST `
            -Body $body `
            -ContentType "application/json" `
            -Headers @{ "X-Gasak-Host" = $DEVICE_HOST; "X-Gasak-Token" = $GASAK_DIST_TOKEN } `
            -TimeoutSec 15 `
            -UseBasicParsing `
            -ErrorAction Stop

        $resp.Content | Set-Content -Path $vaultPath -Encoding UTF8
        ok "Vault synchronized & encrypted"
    } catch {
        warn "Vault offline — using .env fallback mode"
        Remove-Item -Force -ErrorAction SilentlyContinue $vaultPath
    }
}

# PATH injection — tambah INSTALL_DIR ke user PATH
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$INSTALL_DIR*") {
    info "Adding GASAK to user PATH..."
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$INSTALL_DIR", "User")
    ok "PATH updated — restart terminal setelah ini"
} else {
    ok "PATH already configured"
}

Write-Host "  └─"

# ─── DONE ────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║  INSTALLATION COMPLETE                                    ║" -ForegroundColor Green
Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "  Security Status:" -ForegroundColor Cyan
if (Test-Path $vaultPath) {
    $vaultContent = Get-Content $vaultPath -Raw -ErrorAction SilentlyContinue
    if ($vaultContent -match "payload") {
        Write-Host "    [*] Encrypted Vault:   " -NoNewline -ForegroundColor Green
        Write-Host "Active" -ForegroundColor Green
        Write-Host "    [*] Identity Key:      $CONFIG_DIR\id_rsa" -ForegroundColor Green
    }
} else {
    Write-Host "    [!] Encrypted Vault:   " -NoNewline -ForegroundColor Yellow
    Write-Host "Offline (using .env)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Installed Components:" -ForegroundColor Cyan
$checkFiles = @("gasak.exe", "deploy_parkee_win.py", "settlement_rfs.py", "decode_and_merge.py", "log_cleaner.py")
foreach ($f in $checkFiles) {
    $fpath = "$INSTALL_DIR\$f"
    if (Test-Path $fpath) {
        $sz = [math]::Round((Get-Item $fpath).Length / 1KB, 1)
        Write-Host "    [+] $f  (${sz}KB)" -ForegroundColor Green
    } else {
        Write-Host "    [x] $f  (missing)" -ForegroundColor Red
    }
}
if (Test-Path "$AGENT_DIR\server.properties") {
    Write-Host "    [+] server.properties  ($AGENT_DIR)" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Quick Start:" -ForegroundColor Cyan
Write-Host "    1. Restart terminal (atau buka PowerShell baru)" -ForegroundColor DarkGray
Write-Host "    2. Run GASAK:" -ForegroundColor DarkGray
Write-Host "       gasak" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  GASAK Engine • Fadlan's Handmade" -ForegroundColor DarkGray
Write-Host ""
