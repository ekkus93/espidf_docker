param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$idfWrapper = Join-Path $PSScriptRoot "idf.ps1"
if (-not (Test-Path $idfWrapper)) {
  Write-Error "idf.ps1 wrapper not found at $idfWrapper"
  exit 1
}

& $idfWrapper "--" "esptool.py" @Args
exit $LASTEXITCODE
