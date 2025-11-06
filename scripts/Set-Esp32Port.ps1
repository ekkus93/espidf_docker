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
  Write-Host ">> usbipd wsl list" -ForegroundColor Cyan
  usbipd wsl list
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
  # Auto-pick: first "Not attached" device's BUSID
  $lines = (usbipd wsl list) 2>$null
  foreach ($ln in $lines) {
    if ($ln -match '^\s*(\d+-\d+)\s+.+Not\s+attached') {
      $busId = $Matches[1]; break
    }
  }
  if (-not $busId) {
    Write-Error "No 'Not attached' USB device found to auto-attach."
    exit 1
  }
  Write-Host "Auto-selected BUSID: $busId"
} else {
  $busId = Read-Host "Enter BUSID to attach (e.g., 1-2)"
}

# 3) Attach to WSL
Write-Host "Attaching BUSID $busId to '$Distro'…" -ForegroundColor Cyan
$attach = & usbipd wsl attach --busid $busId --distribution $Distro 2>&1
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
