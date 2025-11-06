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
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args,

  [string]$Image  = $(if ($env:IDF_IMAGE) { $env:IDF_IMAGE } else { "espressif/idf:release-v5.5" }),
  [string]$Distro = $(if ($env:IDF_WSL_DISTRO) { $env:IDF_WSL_DISTRO } else { "Ubuntu" })
)

function Test-Command($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

if (-not (Test-Command wsl.exe)) {
  Write-Error "WSL2 is required. Install WSL (wsl.exe) and try again."
  exit 1
}

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
$escapedArgs = $Args | ForEach-Object { Escape-ForBash $_ }
$argList     = $escapedArgs -join " "
$imgEsc      = (Escape-ForBash $Image)
$pwdEsc      = (Escape-ForBash $pwdWsl)

$bash = @"
set -e
$envPrelude
cd $pwdEsc

# Warn when building on Windows-mounted FS (slower I/O than WSL home)
case "\$PWD" in /mnt/*) echo "Note: Project is on /mnt (Windows FS). For faster builds, consider cloning inside your WSL home." ;; esac

# Verify docker is available in WSL
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: 'docker' not found in WSL. Install Docker in WSL or enable Docker Desktop's WSL integration." >&2
  exit 1
fi

# Collect serial devices, if present (for flash/monitor)
DEV_ARGS=()
for d in /dev/ttyUSB* /dev/ttyACM*; do [ -e "\$d" ] && DEV_ARGS+=(--device "\$d:\$d"); done

# Map container user to host (avoid root-owned files)
USER_ARG="--user \$(id -u):\$(id -g)"

# Forward useful env vars from WSL to Docker if set
ENV_ARGS=()
[ -n "\${IDF_GITHUB_ASSETS:-}" ] && ENV_ARGS+=(-e "IDF_GITHUB_ASSETS=\$IDF_GITHUB_ASSETS")
[ -n "\${ESPPORT:-}" ] && ENV_ARGS+=(-e "ESPPORT=\$ESPPORT")
[ -n "\${ESPBAUD:-}" ] && ENV_ARGS+=(-e "ESPBAUD=\$ESPBAUD")

# Run idf.py inside Docker (in WSL)
exec docker run --rm -it \
  \$USER_ARG \
  "\${ENV_ARGS[@]}" \
  -v "\$PWD":/workspace \
  -w /workspace \
  "\${DEV_ARGS[@]}" \
  $imgEsc \
  idf.py $argList
"@

# Execute in the chosen WSL distro
wsl.exe -d $Distro -- bash -lc $bash
exit $LASTEXITCODE
