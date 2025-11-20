<# 
Set-Esp32Port.ps1
- Lists attachable USB devices via `usbipd wsl list`
- Attaches the chosen device to a WSL distro
- Detects /dev/ttyUSB* or /dev/ttyACM* inside WSL
- Sets $env:ESPPORT to the selected device (and optionally persists it)

Usage examples:
  .\Set-Esp32Port.ps1                           # interactively pick a device, attach to Ubuntu, set ESPPORT for this session
  .\Set-Esp32Port.ps1 -Distro Ubuntu -Persist   # persist ESPPORT for future shells (user-level)
  .\Set-Esp32Port.ps1 -Auto                     # auto-pick the first "Not attached" device
  .\Set-Esp32Port.ps1 -Port /dev/ttyUSB0        # skip detection and just set ESPPORT
  .\Set-Esp32Port.ps1 -ListOnly                 # just show devices; make no changes
#>

[CmdletBinding()]
param(
  [string]$Distro = $(if ($env:IDF_WSL_DISTRO) { $env:IDF_WSL_DISTRO } else { "Ubuntu" }),
  [switch]$Auto,
  [switch]$Persist,
  [string]$Port,
  [switch]$ListOnly
  ,[switch]$TryModprobe
)

$script:IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

function Test-CommandAvailable([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' not found in PATH."
  }
}

function Show-UsbList {
  Write-Host ">> usbipd list" -ForegroundColor Cyan
  usbipd list
}

function Get-UsbDeviceState([string]$BusId) {
  $list = (usbipd list) 2>$null
  foreach ($ln in $list) {
    if ($ln -match ('^\s*' + [regex]::Escape($BusId) + '\s')) {
      if ($ln -match '\b(Not\s+shared|Not\s+attached|Attached|Shared)\b') {
        return $Matches[1]
      }
      return $null
    }
  }
  return $null
}

function Confirm-DeviceBound([string]$BusId) {
  $state = Get-UsbDeviceState $BusId
  if (-not $state) {
    Write-Host "Warning: could not determine device state from 'usbipd list'." -ForegroundColor Yellow
    return $null
  }

  if ($state -match 'Not\s+(shared|attached)') {
    Write-Host "Device $BusId is not shared on the host." -ForegroundColor Cyan
    if (-not $script:IsAdmin) {
      Write-Host "Please run in an elevated PowerShell: usbipd bind --busid $BusId" -ForegroundColor Yellow
      Read-Host "Press Enter after completing the bind command" | Out-Null
    } else {
      Write-Host "Binding device on host (requires Admin)..." -ForegroundColor Cyan
      $bindOut = usbipd bind --busid $BusId 2>&1
      if ($LASTEXITCODE -ne 0) {
        Write-Error "usbipd bind failed:`n$bindOut"
        return $null
      }
    }
    # Refresh state after bind attempt
    $state = Get-UsbDeviceState $BusId
  }

  return $state
}

try {
  Test-CommandAvailable "wsl.exe"
  Test-CommandAvailable "usbipd"
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
  Write-Host "Example: idf.ps1 -p $env:ESPPORT flash"
  Write-Host "Example: idf.ps1 -p $env:ESPPORT monitor"
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
Write-Host "Preparing BUSID $busId for attach to '$Distro'..." -ForegroundColor Cyan

$state = Confirm-DeviceBound $busId

# Now attach to WSL (attach usually does not require Admin)
Write-Host "Attaching BUSID $busId to WSL distro '$Distro'..." -ForegroundColor Cyan
# usbipd expects the distro as the argument to --wsl (or -w). Pass the distro before/with --wsl.
$attach = usbipd attach --wsl $Distro --busid $busId 2>&1
if ($LASTEXITCODE -ne 0) {
  if ($attach -match 'already attached') {
    Write-Host "Device is already attached. Detaching from previous client..." -ForegroundColor Yellow
    $detach = usbipd detach --busid $busId 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Error "usbipd detach failed:`n$detach"
      exit 1
    }
    Start-Sleep -Milliseconds 500
    $postDetachState = Confirm-DeviceBound $busId
    if (-not $postDetachState) {
      Write-Error "Device $busId not found after detach. Reconnect the device and try again."
      exit 1
    }
    Write-Host "Re-attaching BUSID $busId..." -ForegroundColor Cyan
    $attach = usbipd attach --wsl $Distro --busid $busId 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Error "usbipd attach failed after detach:`n$attach"
      exit 1
    }
  } else {
    Write-Error "usbipd attach failed:`n$attach"
    exit 1
  }
}

# 4) Detect candidate TTY devices in WSL (retry to allow enumeration)
# Wait longer because device enumeration in WSL can take several seconds.
# Enumerate candidate serial devices inside WSL (skip patterns that do not resolve).
$detectCmd = "ls -1 /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true"
$portCandidates = @()
# Try up to ~15s (30 * 500ms). This reduces false negatives on slower systems.
for ($i=0; $i -lt 30; $i++) {
  $out = wsl.exe -d $Distro -- bash -lc $detectCmd
  $portCandidates = @(
    $out -split "\r?\n" |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_.StartsWith('/dev/tty') }
  )
  if ($portCandidates.Count -gt 0) { break }
  Start-Sleep -Milliseconds 500
}
if ($portCandidates.Count -eq 0) {
  Write-Warning "No /dev/ttyUSB* or /dev/ttyACM* found in WSL. The device may not expose a serial interface, or drivers are still enumerating."
  Write-Host "Gathering quick diagnostics from WSL to help troubleshoot..." -ForegroundColor Yellow
  try {
    Write-Host "--- wsl dmesg (tail) ---" -ForegroundColor Cyan
    $dm = wsl.exe -d $Distro -- bash -lc "dmesg | tail -n 100" 2>&1
    $dm | ForEach-Object { Write-Host $_ }

    Write-Host "--- wsl lsmod (relevant modules) ---" -ForegroundColor Cyan
    $mods = wsl.exe -d $Distro -- bash -lc "lsmod | egrep \"cdc_acm|ch34|ch341|ch34x|usbserial|ftdi_sio\" || true" 2>&1
    if ($mods) { $mods | ForEach-Object { Write-Host $_ } } else { Write-Host "(no matching modules loaded)" }
  } catch {
    Write-Warning "Unable to run diagnostics inside WSL: $_"
  }

  Write-Host "Suggestions:" -ForegroundColor Cyan
  Write-Host " - Ensure WSL distro '$Distro' is running:  wsl -d $Distro" -ForegroundColor Yellow
  Write-Host " - Check dmesg inside WSL for USB enumeration:  wsl -d $Distro -- bash -lc `"dmesg | tail -n 50`"" -ForegroundColor Yellow
  Write-Host " - Try loading likely drivers inside WSL:  wsl -d $Distro -- sudo modprobe cdc_acm" -ForegroundColor Yellow
  Write-Host " - Or manually set the port if you already know it:  .\Set-Esp32Port.ps1 -Port /dev/ttyACM0" -ForegroundColor Yellow

  if ($TryModprobe) {
    Write-Host "Attempting to load common USB-serial drivers inside WSL (will prompt for sudo if needed)..." -ForegroundColor Cyan
    try {
      $mpOut = wsl.exe -d $Distro -- bash -lc "sudo modprobe cdc_acm || true; sudo modprobe ch341 || true; sudo modprobe usbserial || true; dmesg | tail -n 50" 2>&1
      $mpOut | ForEach-Object { Write-Host $_ }
    } catch {
      Write-Warning "Failed to run modprobe attempts: $_"
    }
  }

  Write-Host "You can manually set:  .\Set-Esp32Port.ps1 -Port /dev/ttyUSB0" -ForegroundColor Green
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
Write-Host "USB serial device mapped to $chosen (ESPPORT)" -ForegroundColor Green
if ($Persist) {
  [Environment]::SetEnvironmentVariable("ESPPORT", $chosen, "User")
  Write-Host "ESPPORT persisted for user (reopen shells to pick up)." -ForegroundColor Green
}

Write-Host "Example: idf.ps1 -p $env:ESPPORT flash"
Write-Host "Example: idf.ps1 -p $env:ESPPORT monitor"
