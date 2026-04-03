[CmdletBinding()]
param(
    [string]$DevDir = (Get-Location).Path,
    [int]$SshPort = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ComposeFile = Join-Path $PSScriptRoot "docker-compose.yml"

# Derive a stable instance name from the workspace path
$NormalizedDir = $DevDir.TrimEnd('\', '/').Replace('\', '/').ToLower()
$DirName = Split-Path $NormalizedDir -Leaf
$DirHash = [System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($NormalizedDir)
    )
).Replace('-', '').Substring(0, 8).ToLower()
$InstanceName = "claude-$DirName-$DirHash"

# Auto-assign a stable port from the hash if not specified
if ($SshPort -eq 0) {
    $SshPort = 2200 + [Convert]::ToInt32($DirHash.Substring(0, 4), 16) % 800
}

$env:COMPOSE_PROJECT_NAME = $InstanceName
$env:DEV_DIR = $DevDir
$env:HOME = $env:USERPROFILE
$env:CLAUDE_SSH_PORT = $SshPort

# Per-instance state directory
$env:CLAUDE_STATE_DIR = Join-Path $env:USERPROFILE ".claude-sandbox"
if (-not (Test-Path $env:CLAUDE_STATE_DIR)) {
    New-Item -ItemType Directory -Force -Path $env:CLAUDE_STATE_DIR | Out-Null
}

# Host plugins directory (read-only mount)
$env:HOST_PLUGINS_DIR = Join-Path (Join-Path $env:USERPROFILE ".claude") "plugins"

# Host SSH keys directory (for authorized_keys)
$env:HOST_SSH_DIR = Join-Path $env:USERPROFILE ".ssh"

# Build if images don't exist
docker compose -f $ComposeFile build

# Ensure .claude.json exists in state dir
$ClaudeJson = Join-Path $env:CLAUDE_STATE_DIR ".claude.json"
if (-not (Test-Path $ClaudeJson)) {
    Set-Content -Path $ClaudeJson -Value "{}"
}

# Fix ownership of state directory so container's claude user (UID 1000) can read/write
docker run --rm -v "${env:CLAUDE_STATE_DIR}:/state" alpine chown -R 1000:1000 /state

# Start everything in the background
docker compose -f $ComposeFile up -d

Write-Host "[$InstanceName] workspace: $DevDir  port: $SshPort"

# Wait for sshd to be ready
$retries = 0
while ($retries -lt 15) {
    $result = ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=1 -p $SshPort claude@localhost echo ok 2>&1
    if ($result -eq "ok") { break }
    Start-Sleep -Milliseconds 500
    $retries++
}

# Attach interactively — drops you straight into the claude tmux session
ssh -o StrictHostKeyChecking=no -p $SshPort claude@localhost
