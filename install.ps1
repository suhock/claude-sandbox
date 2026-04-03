# Install claude-sandbox command
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BinDir = Join-Path $env:USERPROFILE ".bin"
$ScriptPath = Join-Path $PSScriptRoot "run.ps1"
$Ps1File = Join-Path $BinDir "claude-sandbox.ps1"
$CmdFile = Join-Path $BinDir "claude-sandbox.cmd"

# Create .bin directory if needed
if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    Write-Host "Created $BinDir"
}

# Write the PowerShell wrapper (handles named parameter forwarding)
Set-Content -Path $Ps1File -Value "& '$ScriptPath' @args"
Write-Host "Created $Ps1File"

# Write the cmd wrapper (calls the ps1 wrapper)
Set-Content -Path $CmdFile -Value "@echo off`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$Ps1File`" %*"
Write-Host "Created $CmdFile"

# Add .bin to user PATH if not already present
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

if ($UserPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$BinDir;$UserPath", "User")
    Write-Host "Added $BinDir to user PATH (restart your terminal for it to take effect)"
}
