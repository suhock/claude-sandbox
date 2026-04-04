[CmdletBinding()]
param(
    [string]$DevDir = (Get-Location).Path,
    [int]$SshPort = 0,
    [string]$Environment,
    [switch]$Rebuild,
    [switch]$Restart,
    [switch]$CopySshKeys
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ValidEnvironments = Get-ChildItem -Directory (Join-Path $PSScriptRoot "environments") | ForEach-Object { $_.Name }

# Handle -CopySshKeys as a standalone command
if ($CopySshKeys -and -not $Environment) {
    $SandboxDir = Join-Path $env:USERPROFILE ".claude-sandbox"
    if (-not (Test-Path $SandboxDir)) {
        New-Item -ItemType Directory -Force -Path $SandboxDir | Out-Null
    }
    $AuthKeysOut = Join-Path $SandboxDir "authorized_keys"
    # Docker creates a directory when mounting a file that doesn't exist yet — clean it up
    if (Test-Path $AuthKeysOut -PathType Container) {
        Remove-Item $AuthKeysOut -Recurse -Force
    }
    $HostSshDir = Join-Path $env:USERPROFILE ".ssh"
    $keys = @()
    foreach ($pub in (Get-ChildItem -Path $HostSshDir -Filter "*.pub" -ErrorAction SilentlyContinue)) {
        $keys += Get-Content $pub.FullName
    }
    $AuthKeysFile = Join-Path $HostSshDir "authorized_keys"
    if (Test-Path $AuthKeysFile) {
        $keys += Get-Content $AuthKeysFile
    }
    if ($keys.Count -eq 0) {
        Write-Error "No public keys found in $HostSshDir"
        exit 1
    }
    $keys | Sort-Object -Unique | Set-Content -Path $AuthKeysOut
    Write-Host ""
    Write-Host "Wrote $($keys.Count) key(s) to $AuthKeysOut"
    Write-Host ""
    if (-not (Test-Path (Join-Path $HostSshDir "*.pub"))) {
        Write-Host "WARNING: No SSH key pair found on this machine." -ForegroundColor Yellow
        Write-Host "  You will not be able to connect from this machine without one." -ForegroundColor Yellow
        Write-Host "  Generate a key pair with: ssh-keygen -t ed25519" -ForegroundColor Yellow
        Write-Host ""
    }
    exit 0
}

if (-not $Environment) {
    # Try to infer environment from previously used instances for this directory
    $NormDir = $DevDir.TrimEnd('\', '/').Replace('\', '/').ToLower()
    $DirLeaf = Split-Path $NormDir -Leaf
    $SandboxDir = Join-Path $env:USERPROFILE ".claude-sandbox"
    $MatchedEnvs = @()
    if (Test-Path $SandboxDir) {
        foreach ($env_ in $ValidEnvironments) {
            $h = [System.BitConverter]::ToString(
                [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes("${NormDir}:${env_}")
                )
            ).Replace('-', '').Substring(0, 8).ToLower()
            $candidate = Join-Path $SandboxDir "claude-$DirLeaf-$env_-$h"
            if (Test-Path $candidate) {
                $MatchedEnvs += $env_
            }
        }
    }
    if ($MatchedEnvs.Count -eq 1) {
        $Environment = $MatchedEnvs[0]
        Write-Host "Using environment: $Environment (inferred from previous use)"
    } else {
        if ($MatchedEnvs.Count -gt 1) {
            Write-Host ""
            Write-Host "Multiple environments found for this directory: $($MatchedEnvs -join ', ')"
            Write-Host "Please specify one with -Environment <name>"
            Write-Host ""
            exit 1
        }
        Write-Host ""
        Write-Host "Usage:"
        Write-Host "  claude-sandbox -Environment <name> [-DevDir <path>] [-SshPort <port>] [-Rebuild]"
        Write-Host "  claude-sandbox -Environment <name> -Restart"
        Write-Host "  claude-sandbox -CopySshKeys"
        Write-Host ""
        Write-Host "Environments: $($ValidEnvironments -join ', ')"
        Write-Host ""
        Write-Host "Options:"
        Write-Host "  -Environment  Runtime environment"
        Write-Host "  -DevDir       Workspace directory (default: current directory)"
        Write-Host "  -SshPort      SSH port (default: auto-assigned)"
        Write-Host "  -Rebuild      Force rebuild without cache"
        Write-Host "  -Restart      Stop and restart the container (picks up new mounts)"
        Write-Host "  -CopySshKeys  Populate ~/.claude-sandbox/authorized_keys from ~/.ssh"
        Write-Host ""
        exit 0
    }
}

if ($Environment -notin $ValidEnvironments) {
    Write-Error "Unknown environment: $Environment. Valid options: $($ValidEnvironments -join ', ')"
    exit 1
}

$ComposeBase = Join-Path $PSScriptRoot "docker-compose.yml"
$ComposeEnv = Join-Path $PSScriptRoot "environments" $Environment "compose.yml"
$ComposeArgs = @("-f", $ComposeBase, "-f", $ComposeEnv)

# Derive a stable instance name from the workspace path
$NormalizedDir = $DevDir.TrimEnd('\', '/').Replace('\', '/').ToLower()
$DirName = Split-Path $NormalizedDir -Leaf
$InstanceHash = [System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes("${NormalizedDir}:${Environment}")
    )
).Replace('-', '').Substring(0, 8).ToLower()
$InstanceName = "claude-$DirName-$Environment-$InstanceHash"

# Auto-assign a stable port from the hash if not specified
if ($SshPort -eq 0) {
    $SshPort = 2200 + [Convert]::ToInt32($InstanceHash.Substring(0, 4), 16) % 800
}

$env:COMPOSE_PROJECT_NAME = $InstanceName
$env:SANDBOX_ROOT = $PSScriptRoot
$env:SANDBOX_ENV = $Environment
$env:SANDBOX_WORKSPACE = (Split-Path $DevDir -Leaf)
$env:DEV_DIR = $DevDir
$env:HOME = $env:USERPROFILE
$env:CLAUDE_SSH_PORT = $SshPort

# Per-instance state directory
$env:CLAUDE_STATE_DIR = Join-Path (Join-Path $env:USERPROFILE ".claude-sandbox") $InstanceName
if (-not (Test-Path $env:CLAUDE_STATE_DIR)) {
    New-Item -ItemType Directory -Force -Path $env:CLAUDE_STATE_DIR | Out-Null
}

# Host plugins directory (read-only mount)
$env:HOST_PLUGINS_DIR = Join-Path (Join-Path $env:USERPROFILE ".claude") "plugins"

# SSH authorized keys file — shared across all instances, user-managed
# Always ensure the file exists so Docker mounts a file, not /dev/null
$env:SANDBOX_AUTHORIZED_KEYS = Join-Path (Join-Path $env:USERPROFILE ".claude-sandbox") "authorized_keys"
# Docker creates a directory when mounting a file that doesn't exist yet — clean it up
if (Test-Path $env:SANDBOX_AUTHORIZED_KEYS -PathType Container) {
    Remove-Item $env:SANDBOX_AUTHORIZED_KEYS -Recurse -Force
}
if (-not (Test-Path $env:SANDBOX_AUTHORIZED_KEYS)) {
    New-Item -ItemType File -Force -Path $env:SANDBOX_AUTHORIZED_KEYS | Out-Null
}
$HasAuthorizedKeys = (Get-Item $env:SANDBOX_AUTHORIZED_KEYS).Length -gt 0

function Show-SshWarnings {
    if (-not $HasAuthorizedKeys) {
        Write-Host "WARNING: No SSH keys configured. You will not be able to connect." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Add public keys to: $($env:SANDBOX_AUTHORIZED_KEYS)" -ForegroundColor Yellow
        Write-Host "  Or re-run with -CopySshKeys to import from ~/.ssh" -ForegroundColor Yellow
        Write-Host ""
    }
    $HostSshDir = Join-Path $env:USERPROFILE ".ssh"
    if (-not (Test-Path (Join-Path $HostSshDir "*.pub"))) {
        Write-Host "WARNING: No SSH key pair found on this machine." -ForegroundColor Yellow
        Write-Host "  You will not be able to connect from this machine without one." -ForegroundColor Yellow
        Write-Host "  Generate a key pair with: ssh-keygen -t ed25519" -ForegroundColor Yellow
        Write-Host ""
    }
}

# Check if already running
$running = docker compose @ComposeArgs ps --status running --format "{{.Name}}" 2>$null
if ($running -match $Environment) {
    if ($Rebuild) {
        Write-Host "[$InstanceName] rebuilding..."
        docker compose @ComposeArgs down
    } elseif ($Restart) {
        Write-Host "[$InstanceName] restarting..."
        docker compose @ComposeArgs down
    } else {
        Write-Host ""
        Write-Host "[$InstanceName] already running ($Environment)"
        Write-Host ""
        Write-Host "  ssh -p $SshPort claude@localhost"
        Write-Host ""
        Show-SshWarnings
        exit 0
    }
}

# Build environment image
docker compose @ComposeArgs build $(if ($Rebuild) { "--no-cache" })

# Ensure .claude.json exists in state dir
$ClaudeJson = Join-Path $env:CLAUDE_STATE_DIR ".claude.json"
if (-not (Test-Path $ClaudeJson)) {
    Set-Content -Path $ClaudeJson -Value "{}"
}

# Fix ownership of state directory so container's claude user (UID 1000) can read/write
docker run --rm -v "${env:CLAUDE_STATE_DIR}:/state" alpine chown -R 1000:1000 /state

# Remove stale SSH host key for this port (container gets new key on rebuild)
ssh-keygen -R "[localhost]:$SshPort" 2>$null

# Start everything in the background
docker compose @ComposeArgs up -d

# Wait for sshd to be ready
$ErrorActionPreference = "Continue"
$retries = 0
while ($retries -lt 15) {
    $result = ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=1 -p $SshPort claude@localhost echo ok 2>&1
    if ("$result" -eq "ok") { break }
    Start-Sleep -Milliseconds 500
    $retries++
}
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "[$InstanceName] workspace: $DevDir ($Environment)"
Write-Host ""
Write-Host "  ssh -p $SshPort claude@localhost"
Write-Host ""
Show-SshWarnings
