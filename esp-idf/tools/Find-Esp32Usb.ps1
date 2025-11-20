<#
Find-Esp32Usb.ps1
Prompts you to unplug and then reconnect the ESP32 so it can identify the fresh USB entry
reported by `usbipd list`. The script prints the BusId, VID:PID, description, and state for any
new device that appears after the reconnect step.
#>

[CmdletBinding()]
param()

function Test-CommandAvailable {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' not found in PATH."
  }
}

function Get-UsbipdConnectedDevices {
  $raw = usbipd list
  $devices = @()
  $inConnected = $false

  foreach ($line in $raw) {
    if ($line -match '^\s*Connected:') {
      $inConnected = $true
      continue
    }

    if (-not $inConnected) { continue }
    if ($line -match '^\s*Persisted:') { break }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    if ($line -match '^\s*(\S+)\s+([0-9A-Fa-f]{4}:[0-9A-Fa-f]{4})\s+(.*?)\s{2,}(\S.*)$') {
      $devices += [pscustomobject]@{
        BusId       = $Matches[1]
        VidPid      = $Matches[2]
        Description = $Matches[3].Trim()
        State       = $Matches[4].Trim()
      }
    }
  }

  return $devices
}

try {
  Test-CommandAvailable 'usbipd'
} catch {
  Write-Error $_.Exception.Message
  exit 1
}

Write-Host 'Unplug the ESP32 USB cable, then press Enter to continue.' -ForegroundColor Cyan
Read-Host | Out-Null
$before = Get-UsbipdConnectedDevices

Write-Host "Captured $($before.Count) currently connected device(s)." -ForegroundColor DarkGray

Write-Host 'Now plug in the ESP32, wait for it to enumerate, then press Enter.' -ForegroundColor Cyan
Read-Host | Out-Null
$after = Get-UsbipdConnectedDevices

Write-Host "Captured $($after.Count) device(s) after reconnect." -ForegroundColor DarkGray

$beforeIndex = @{}
foreach ($dev in $before) { $beforeIndex[$dev.BusId] = $true }

$newDevices = @()
foreach ($dev in $after) {
  if (-not $beforeIndex.ContainsKey($dev.BusId)) {
    $newDevices += $dev
  }
}

if ($newDevices.Count -eq 0) {
  Write-Warning 'No new BusId detected. The device may have kept the same BusId or was already attached.'
  Write-Host 'Tip: run `usbipd state` to inspect detailed instance information if needed.' -ForegroundColor Yellow
  exit 1
}

Write-Host 'New USB device(s) detected:' -ForegroundColor Green
foreach ($dev in $newDevices) {
  Write-Host "  BusId: $($dev.BusId)" -ForegroundColor Green
  Write-Host "  VID:PID: $($dev.VidPid)"
  Write-Host "  Description: $($dev.Description)"
  Write-Host "  State: $($dev.State)"
  Write-Host ''
}

Write-Host 'You can now use the detected BusId with Set-Esp32Port.ps1 or usbipd attach.' -ForegroundColor Cyan
