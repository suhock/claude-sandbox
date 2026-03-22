[CmdletBinding()]
param(
    [string]$DevDir = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#$BackupDir = Join-Path $env:USERPROFILE "dev-git-backups"
$ComposeFile = Join-Path $PSScriptRoot "docker-compose.yml"

# Validate dev directory
#if (-not (Test-Path (Join-Path $DevDir ".git"))) {
#    Write-Error "${DevDir} is not a git repository."
#    exit 1
#}

# Snapshot .git outside the workspace before every session
#New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
#$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
#$Backup = Join-Path $BackupDir $Timestamp
#Write-Host "Snapshotting .git to ${Backup} ..."
#Copy-Item -Recurse (Join-Path $DevDir ".git") $Backup

$env:DEV_DIR = $DevDir
$env:HOME = $env:USERPROFILE
$env:CLAUDE_DIR = Join-Path $env:USERPROFILE ".claude"
$env:CLAUDE_JSON = Join-Path $env:USERPROFILE ".claude.json"

$ClaudeJson = Join-Path $env:USERPROFILE ".claude.json"
if (-not (Test-Path $ClaudeJson)) {
    New-Item -ItemType File -Force -Path $ClaudeJson | Out-Null
}
$env:CLAUDE_JSON = $ClaudeJson

# Build if images don't exist
docker compose -f $ComposeFile build

# Start proxy in background, run claude interactively, tear down on exit
try {
    docker compose -f $ComposeFile run --rm claude
} finally {
    docker compose -f $ComposeFile stop proxy
}
