# Install claude-sandbox command
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BinDir = Join-Path $env:USERPROFILE ".bin"
$ScriptPath = Join-Path $PSScriptRoot "run.ps1"
$CmdFile = Join-Path $BinDir "claude-sandbox.cmd"

# Create .bin directory if needed
if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    Write-Host "Created $BinDir"
}

# Write the wrapper script
Set-Content -Path $CmdFile -Value "@echo off`npowershell -NoProfile -File `"$ScriptPath`" %*"
Write-Host "Created $CmdFile"

# Add .bin to user PATH if not already present
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

if ($UserPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$BinDir;$UserPath", "User")
    Write-Host "Added $BinDir to user PATH (restart your terminal for it to take effect)"
}
