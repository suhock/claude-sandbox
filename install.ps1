# Install claude-sandbox command
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BinDir = Join-Path $env:USERPROFILE ".bin"
$ScriptPath = Join-Path $PSScriptRoot "run.ps1"
$Ps1File = Join-Path $BinDir "claude-sandbox.ps1"

# Create .bin directory if needed
if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    Write-Host "Created $BinDir"
}

# Write the PowerShell wrapper with parameter declarations for tab completion
$Ps1Content = @"
[CmdletBinding()]
param(
    [string]`$DevDir,
    [int]`$SshPort,
    [string]`$Environment,
    [switch]`$Rebuild,
    [switch]`$Restart,
    [switch]`$CopySshKeys,
    [switch]`$Connect
)
& '$ScriptPath' @PSBoundParameters
"@
Set-Content -Path $Ps1File -Value $Ps1Content
Write-Host "Created $Ps1File"

# Write argument completer registration script for -Environment
$CompleterDir = Join-Path $BinDir ".completions"
if (-not (Test-Path $CompleterDir)) {
    New-Item -ItemType Directory -Force -Path $CompleterDir | Out-Null
}
$CompleterFile = Join-Path $CompleterDir "claude-sandbox.ps1"
$EnvDir = Join-Path $PSScriptRoot "environments"
$CompleterContent = @"
# Tab completion for claude-sandbox -Environment parameter
Register-ArgumentCompleter -CommandName claude-sandbox,claude-sandbox.ps1 -ParameterName Environment -ScriptBlock {
    param(`$commandName, `$parameterName, `$wordToComplete, `$commandAst, `$fakeBoundParameters)
    Get-ChildItem -Directory '$EnvDir' |
        Where-Object { `$_.Name -like "`$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(`$_.Name, `$_.Name, 'ParameterValue', `$_.Name)
        }
}
"@
Set-Content -Path $CompleterFile -Value $CompleterContent
Write-Host "Created $CompleterFile"

# Add .bin to user PATH if not already present
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

if ($UserPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$BinDir;$UserPath", "User")
    Write-Host "Added $BinDir to user PATH (restart your terminal for it to take effect)"
}

# Add completer to PowerShell profile so tab completion works in every session
$ProfileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $ProfileDir)) {
    New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
}
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Force -Path $PROFILE | Out-Null
}
$SourceLine = ". '$CompleterFile'"
$ProfileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if (-not $ProfileContent -or $ProfileContent -notlike "*.completions*claude-sandbox*") {
    Add-Content -Path $PROFILE -Value "`n# claude-sandbox tab completion`n$SourceLine"
    Write-Host "Added tab completion to PowerShell profile ($PROFILE)"
}
