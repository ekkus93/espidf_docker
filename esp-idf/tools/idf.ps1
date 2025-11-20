<#
  idf.ps1 — Windows PowerShell wrapper that runs *all* ESP-IDF commands via WSL2.
  - Requires: WSL2, Docker available inside WSL, and usbipd (for serial devices).
  - Usage:
      idf.py set-target esp32
      idf.py build
      idf.py -p /dev/ttyUSB0 -b 921600 flash
      idf.py monitor
      idf.py fullclean
  - Optional params / env:
      -Image  (or env IDF_IMAGE)        : Docker image (default espressif/idf:release-v5.5)
      -Distro (or env IDF_WSL_DISTRO)   : WSL distro (default "Ubuntu")
#>

param(
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$IdfArgs,

  [string]$Image  = $(if ($env:IDF_IMAGE) { $env:IDF_IMAGE } else { "espressif/idf:release-v5.5" }),
  [string]$Distro = $(if ($env:IDF_WSL_DISTRO) { $env:IDF_WSL_DISTRO } else { "Ubuntu" })
)

function Test-Command($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

function Get-WslUnixTime([string]$distro) {
  try {
    $output = & wsl.exe -d $distro -- bash -lc "date +%s"
    if ($LASTEXITCODE -ne 0) { return $null }
    return [long]($output.Trim())
  } catch {
    return $null
  }
}

function Sync-WslClock([string]$distro, [int]$thresholdSeconds = 2) {
  $wslTime = Get-WslUnixTime $distro
  if ($null -eq $wslTime) { return }

  $winTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $skew = [Math]::Abs($winTime - $wslTime)
  if ($skew -le $thresholdSeconds) { return }

  Write-Host "WSL clock skew detected (~${skew}s); restarting WSL for resync..." -ForegroundColor Yellow
  & wsl.exe --shutdown | Out-Null
  Start-Sleep -Seconds 2

  $wslTime = Get-WslUnixTime $distro
  if ($null -eq $wslTime) {
    Write-Warning "Unable to verify WSL clock after restart; continuing anyway."
    return
  }

  $winTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $skew = [Math]::Abs($winTime - $wslTime)
  if ($skew -gt $thresholdSeconds) {
    Write-Warning "WSL clock still differs by ~${skew}s; manual sync may be required."
  }
}

if (-not (Test-Command wsl.exe)) {
  Write-Error "WSL2 is required. Install WSL (wsl.exe) and try again."
  exit 1
}

Sync-WslClock $Distro

# Convert Windows path (e.g., C:\foo\bar) to WSL (/mnt/c/foo/bar)
function Convert-ToWslPath([string]$winPath) {
  if ($winPath -match '^[A-Za-z]:') {
    $drive = $winPath.Substring(0,1).ToLower()
    $rest  = $winPath.Substring(2) -replace '\\','/'
    return "/mnt/$drive/$rest"
  }
  # Fallback for UNC; best-effort mapping
  return "/mnt/c/$(($winPath -replace '^\\\\','') -replace '\\','/')"
}

# Quote for safe bash usage
function Escape-ForBash([string]$s) { return "'" + ($s -replace "'", "'\''") + "'" }

$pwdWin = (Get-Location).Path
$pwdWsl = Convert-ToWslPath $pwdWin

# ----- Patch (option 1): env prelude -----
# Collect *Windows* env vars we want visible inside WSL before running Docker.
$winEnv = @{}
foreach ($k in @('ESPPORT','ESPBAUD','IDF_GITHUB_ASSETS','IDF_IMAGE')) {
  $v = [System.Environment]::GetEnvironmentVariable($k, "Process")
  if (-not $v) { $v = [System.Environment]::GetEnvironmentVariable($k, "User") }
  if ($v) { $winEnv[$k] = $v }
}
# Turn them into "export ..." lines for the WSL bash snippet.
$envPrelude = ($winEnv.GetEnumerator() | ForEach-Object {
  "export $($_.Key)=" + (Escape-ForBash $_.Value)
}) -join "`n"
# -----------------------------------------

# Build a bash snippet to run inside WSL
$escapedArgs = $IdfArgs | ForEach-Object { Escape-ForBash $_ }
$argList     = if ($escapedArgs.Count -gt 0) { ' ' + ($escapedArgs -join ' ') } else { '' }
$imgEsc      = (Escape-ForBash $Image)
$pwdEsc      = (Escape-ForBash $pwdWsl)

$bashTemplate = @'
#!/bin/bash
set -e
{ENV_PRELUDE}
cd {PWD_ESC}

# Verify docker is available in WSL
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: 'docker' not found in WSL. Install Docker in WSL or enable Docker Desktop's WSL integration." >&2
  exit 1
fi

# Collect serial devices, if present (for flash/monitor)
DEV_ARGS=()
for d in /dev/ttyUSB* /dev/ttyACM*; do [ -e "$d" ] && DEV_ARGS+=(--device "$d:$d"); done

# Map container user to host (avoid root-owned files)
USER_ARG="--user $(id -u):$(id -g)"

# Forward useful env vars from WSL to Docker if set
ENV_ARGS=()
[ -n "${IDF_GITHUB_ASSETS:-}" ] && ENV_ARGS+=(-e "IDF_GITHUB_ASSETS=$IDF_GITHUB_ASSETS")
[ -n "${ESPPORT:-}" ] && ENV_ARGS+=(-e "ESPPORT=$ESPPORT")
[ -n "${ESPBAUD:-}" ] && ENV_ARGS+=(-e "ESPBAUD=$ESPBAUD")

# Silence git safe.directory warnings inside the container for ESP-IDF-owned directories
ENV_ARGS+=(-e GIT_CONFIG_COUNT=2)
ENV_ARGS+=(-e GIT_CONFIG_KEY_0=safe.directory)
ENV_ARGS+=(-e GIT_CONFIG_VALUE_0=/opt/esp/idf)
ENV_ARGS+=(-e GIT_CONFIG_KEY_1=safe.directory)
ENV_ARGS+=(-e GIT_CONFIG_VALUE_1=/opt/esp/idf/components/openthread/openthread)

# Run idf.py inside Docker (in WSL)
exec docker run --rm -it \
  $USER_ARG \
  "${ENV_ARGS[@]}" \
  -v "$PWD":/workspace \
  -w /workspace \
  "${DEV_ARGS[@]}" \
  {IMG_ESC} \
  idf.py{ARG_LIST}
'@

$bash = $bashTemplate.Replace('{ENV_PRELUDE}', $envPrelude)
$bash = $bash.Replace('{PWD_ESC}', $pwdEsc)
$bash = $bash.Replace('{IMG_ESC}', $imgEsc)
$bash = $bash.Replace('{ARG_LIST}', $argList)
$bash = $bash -replace "`r", ""

$tempScript = [System.IO.Path]::GetTempFileName()
$exitCode = 1
try {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($tempScript, $bash, $utf8NoBom)
  $tempScriptWsl = Convert-ToWslPath $tempScript
  $runCmd = "bash " + (Escape-ForBash $tempScriptWsl)

  wsl.exe -d $Distro -- bash -lc $runCmd
  $exitCode = $LASTEXITCODE
} finally {
  Remove-Item $tempScript -ErrorAction SilentlyContinue
}

exit $exitCode
