<# 
Set-IdfPort.ps1
- Lists attachable USB devices via `usbipd wsl list`
- Attaches the chosen device to a WSL distro
- Detects /dev/ttyUSB* or /dev/ttyACM* inside WSL
- Sets $env:ESPPORT to the selected device (and optionally persists it)

Usage examples:
  .\Set-IdfPort.ps1                           # interactively pick a device, attach to Ubuntu, set ESPPORT for this session
  .\Set-IdfPort.ps1 -Distro Ubuntu -Persist   # persist ESPPORT for future shells (user-level)
  .\Set-IdfPort.ps1 -Auto                     # auto-pick the first "Not attached" device
  .\Set-IdfPort.ps1 -Port /dev/ttyUSB0        # skip detection and just set ESPPORT
  .\Set-IdfPort.ps1 -ListOnly                 # just show devices; make no changes
#>

[CmdletBinding()]
param(
  [string]$Distro = $(if ($env:IDF_WSL_DISTRO) { $env:IDF_WSL_DISTRO } else { "Ubuntu" }),
  [switch]$Auto,
  [switch]$Persist,
  [string]$Port,
  [switch]$ListOnly
)

function Require-Cmd([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' not found in PATH."
  }
}

function Show-UsbList {
  Write-Host ">> usbipd list" -ForegroundColor Cyan
  usbipd list
}

try {
  Require-Cmd "wsl.exe"
  Require-Cmd "usbipd"
} catch {
  Write-Error $_.Exception.Message
  Write-Host "Install WSL2 and usbipd (e.g. 'winget install usbipd')." -ForegroundColor Yellow
  exit 1
}

if ($ListOnly) { Show-UsbList; exit 0 }

# If user provided a concrete /dev path, just set ESPPORT and optionally persist.
if ($Port) {
  $env:ESPPORT = $Port
  Write-Host "ESPPORT set to $Port for this session." -ForegroundColor Green
  if ($Persist) {
    [Environment]::SetEnvironmentVariable("ESPPORT", $Port, "User")
    Write-Host "ESPPORT persisted for user (reopen shells to pick up)." -ForegroundColor Green
  }
  Write-Host "Example: idf.py -p $env:ESPPORT flash"
  exit 0
}

# 1) List devices
Show-UsbList

# 2) Choose BUSID
$busId = $null
if ($Auto) {
  # Auto-pick: first device that appears Not shared / Not attached
  $lines = (usbipd list) 2>$null
  foreach ($ln in $lines) {
    if ($ln -match '^\s*(\d+-\d+)\s+' -and ($ln -match 'Not\s+shared' -or $ln -match 'Not\s+attached')) {
      $busId = $Matches[1]; break
    }
  }
  if (-not $busId) {
    Write-Error "No 'Not shared' USB device found to auto-attach."
    exit 1
  }
  Write-Host "Auto-selected BUSID: $busId"
} else {
  $busId = Read-Host "Enter BUSID to attach (e.g., 1-2)"
}

# 3) Ensure device is bound (shared) on the host then attach to WSL
Write-Host "Preparing BUSID $busId for attach to '$Distro'…" -ForegroundColor Cyan

# Check current state for the selected BUSID
$state = $null
$listOut = (usbipd list) 2>$null
foreach ($ln in $listOut) {
  if ($ln -match '^\s*('+[regex]::Escape($busId)+')\s+.+' ) {
    if ($ln -match '\b(Not\s+shared|Not\s+attached|Attached|Shared)\b') { $state = $Matches[1] }
    break
  }
}

if (-not $state) { Write-Host "Warning: could not determine device state from 'usbipd list'. Proceeding to attach." -ForegroundColor Yellow }

# If device is not shared/attached on the host, user must bind (requires Admin)
if ($state -and ($state -match 'Not\s+(shared|attached)')) {
  Write-Host "Device appears unshared on the host. A host 'bind' is required (admin)." -ForegroundColor Cyan
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
  if (-not $isAdmin) {
    Write-Host "Please run the following in an elevated PowerShell to bind the device (or re-run this script as Administrator):" -ForegroundColor Yellow
    Write-Host "    usbipd bind --busid $busId" -ForegroundColor Green
    Read-Host "Press Enter after you have run the bind command in an Administrator PowerShell"
  } else {
    Write-Host "Binding device on host (requires Admin)…" -ForegroundColor Cyan
    $bindOut = usbipd bind --busid $busId 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Error "usbipd bind failed:`n$bindOut"
      exit 1
    }
  }
}

# Now attach to WSL (attach usually does not require Admin)
Write-Host "Attaching BUSID $busId to WSL distro '$Distro'…" -ForegroundColor Cyan
$attach = usbipd attach --wsl --busid $busId --distribution $Distro 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Error "usbipd attach failed:`n$attach"
  exit 1
}

# 4) Detect candidate TTY devices in WSL (retry briefly to allow enumeration)
$detectCmd = "for d in /dev/ttyUSB* /dev/ttyACM*; do [ -e `"`$d`" ] && echo `"`$d`"; done"
$portCandidates = @()
for ($i=0; $i -lt 10; $i++) {
  $out = wsl.exe -d $Distro -- bash -lc $detectCmd
  $portCandidates = $out -split "`r?`n" | Where-Object { $_ -and -not $_.StartsWith("Note:") }
  if ($portCandidates.Count -gt 0) { break }
  Start-Sleep -Milliseconds 300
}
if ($portCandidates.Count -eq 0) {
  Write-Warning "No /dev/ttyUSB* or /dev/ttyACM* found in WSL. The device may not expose a serial interface, or drivers are still enumerating."
  Write-Host "You can manually set:  .\Set-IdfPort.ps1 -Port /dev/ttyUSB0"
  exit 1
}

# 5) Choose the port if multiple; otherwise take the single candidate
$chosen = $null
if ($portCandidates.Count -eq 1) {
  $chosen = $portCandidates[0]
  Write-Host "Detected serial device: $chosen" -ForegroundColor Green
} else {
  Write-Host "Multiple serial devices detected:" -ForegroundColor Yellow
  $portCandidates | ForEach-Object { Write-Host "  $_" }
  $chosen = Read-Host "Enter device to use as ESPPORT"
}

# 6) Set (and optionally persist) ESPPORT in Windows env; your idf.ps1 wrapper will forward it
$env:ESPPORT = $chosen
Write-Host "ESPPORT set to $chosen for this session." -ForegroundColor Green
if ($Persist) {
  [Environment]::SetEnvironmentVariable("ESPPORT", $chosen, "User")
  Write-Host "ESPPORT persisted for user (reopen shells to pick up)." -ForegroundColor Green
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  idf.py -p $env:ESPPORT flash"
Write-Host "  idf.py -p $env:ESPPORT monitor"
