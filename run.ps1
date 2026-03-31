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

# Local directory for sandbox Claude state (isolated from host ~/.claude)
$env:CLAUDE_STATE_DIR = Join-Path $env:USERPROFILE ".claude-sandbox"
if (-not (Test-Path $env:CLAUDE_STATE_DIR)) {
    New-Item -ItemType Directory -Force -Path $env:CLAUDE_STATE_DIR | Out-Null
}

# Host plugins directory (read-only mount)
$env:HOST_PLUGINS_DIR = Join-Path (Join-Path $env:USERPROFILE ".claude") "plugins"

# Build if images don't exist
docker compose -f $ComposeFile build

# Ensure .claude.json exists in state dir
$ClaudeJson = Join-Path $env:CLAUDE_STATE_DIR ".claude.json"
if (-not (Test-Path $ClaudeJson)) {
    Set-Content -Path $ClaudeJson -Value "{}"
}

# Fix ownership of state directory so container's claude user (UID 1000) can read/write
docker run --rm -v "${env:CLAUDE_STATE_DIR}:/state" alpine chown -R 1000:1000 /state

# Ensure proxy is running (idempotent — won't restart if already up)
docker compose -f $ComposeFile up -d proxy

# Run claude interactively; proxy stays up after exit
docker compose -f $ComposeFile run --service-ports --rm claude
