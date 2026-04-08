[CmdletBinding()]
param(
    [string]$WorkDir = (Get-Location).Path,
    [int]$SshPort = 0,
    [string]$Environment,
    [switch]$Start,
    [switch]$Rebuild,
    [switch]$Restart,
    [switch]$CopySshKeys,
    [switch]$Connect,
    [switch]$AddFirewallRule,
    [switch]$SandboxDev
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Sandbox config directory (shared across all instances)
$SandboxDir = Join-Path $env:USERPROFILE ".claude-sandbox"

if (-not (Test-Path $SandboxDir)) {
    New-Item -ItemType Directory -Force -Path $SandboxDir | Out-Null
}

$AuthorizedKeysFile = Join-Path $SandboxDir "authorized_keys"

# The list of valid values for -Environment
$ValidEnvironments = Get-ChildItem -Directory (Join-Path $PSScriptRoot "environments") | ForEach-Object { $_.Name }

# --- Functions ---

function Main {
    $ExclusiveFlags = @(@($Start, $Rebuild, $Restart, $Connect, $CopySshKeys, $AddFirewallRule) | Where-Object { $_ })
    if ($SandboxDev -and ($Connect -or $CopySshKeys -or $AddFirewallRule)) {
        Write-Error "-SandboxDev can only be used with -Start, -Rebuild, or -Restart"
        exit 1
    }

    if ($ExclusiveFlags.Count -gt 1) {
        Write-Error "Only one of -Start, -Rebuild, -Restart, -Connect, -CopySshKeys, -AddFirewallRule can be specified"
        exit 1
    }

    if ($CopySshKeys) {
        exit (Invoke-CopySshKeys)
    }

    if (-not $Environment) {
        Resolve-Environment
    }

    if (-not $Environment) {
        Show-Usage
        exit 0
    }

    if ($Environment -notin $ValidEnvironments) {
        Write-Error ""
        Write-Error "Unknown environment: $Environment. Valid options: $($ValidEnvironments -join ', ')"
        Write-Error ""
        exit 1
    }

    if ($AddFirewallRule) {
        exit (Invoke-AddFirewallRule)
    }

    if ($Connect) {
        Invoke-Connect
    } elseif ($Restart) {
        Invoke-Restart
    } elseif ($Rebuild) {
        Invoke-Rebuild
    } else {  # -Start or default
        Invoke-Start
    }
}

function Show-Usage {
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  claude-sandbox [-Start] [-Environment <name>] [-WorkDir <path>]"
    Write-Host "                 [-SshPort <port>]"
    Write-Host "  claude-sandbox -Restart [-Environment <name>] [-WorkDir <path>]"
    Write-Host "                 [-SshPort <port>]"
    Write-Host "  claude-sandbox -Rebuild [-Environment <name>] [-WorkDir <path>]"
    Write-Host "                 [-SshPort <port>]"
    Write-Host "  claude-sandbox -Connect [-Environment <name>]"
    Write-Host "  claude-sandbox -CopySshKeys"
    Write-Host "  claude-sandbox -AddFirewallRule [-Environment <name>]"
    Write-Host ""
    Write-Host "Environments: $($ValidEnvironments -join ', ')"
    Write-Host ""
    Write-Host "Commands (default: -Start):"
    Write-Host "  -Start            Start the sandbox (build if necessary)"
    Write-Host "  -Restart          Stop and restart the container"
    Write-Host "  -Rebuild          Force rebuild the container image"
    Write-Host "  -Connect          SSH into the container"
    Write-Host "  -CopySshKeys      Populate ~/.claude-sandbox/authorized_keys from ~/.ssh"
    Write-Host "  -AddFirewallRule  Open the SSH port in Windows Firewall (requests UAC)"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Environment  Runtime environment (inferred if only one exists for directory)"
    Write-Host "  -WorkDir       Workspace directory (default: current directory)"
    Write-Host "  -SshPort      SSH port (default: auto-assigned)"
    Write-Host ""
}

function Get-InstanceName([string]$Env) {
    $NormalizedWorkDir = $WorkDir.TrimEnd('\', '/').Replace('\', '/').ToLower()
    $WorkDirName = Split-Path $NormalizedWorkDir -Leaf

    $hash = [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes("${NormalizedWorkDir}:${Env}")
        )
    ).Replace('-', '').Substring(0, 8).ToLower()

    "claude-$WorkDirName-$Env-$hash"
}

function Get-SshPort([string]$InstanceName) {
    if ($SshPort -ne 0) { return $SshPort }
    $PortHash = $InstanceName.Substring($InstanceName.LastIndexOf('-') + 1)
    22001 + [Convert]::ToInt32($PortHash.Substring(0, 4), 16) % 999
}

function Resolve-Environment {
    $MatchedEnvs = @()

    foreach ($env_ in $ValidEnvironments) {
        $candidate = Join-Path $SandboxDir (Get-InstanceName $env_)
        if (Test-Path $candidate) {
            $MatchedEnvs += $env_
        }
    }

    if ($MatchedEnvs.Count -eq 1) {
        $script:Environment = $MatchedEnvs[0]
        Write-Host "Using environment: $($script:Environment) (inferred from previous use)"
    } elseif ($MatchedEnvs.Count -gt 1) {
        Write-Host ""
        Write-Host "Multiple environments found for this directory: $($MatchedEnvs -join ', ')"
        Write-Host "Please specify one with -Environment <name>"
        Write-Host ""
        exit 1
    }
}

function Invoke-AddFirewallRule {
    if (-not $Environment) {
        Write-Error "-AddFirewallRule requires -Environment"
        return 1
    }

    $name = Get-InstanceName $Environment
    $port = Get-SshPort $name
    $PickerPort = $env:PICKER_SSH_PORT
    if (-not $PickerPort) { $PickerPort = 22000 }

    $rules = @(
        @{ Name = "Claude Sandbox - $name"; Port = $port },
        @{ Name = "Claude Sandbox Picker"; Port = $PickerPort }
    )

    # Filter to only rules that don't already exist
    $needed = @()
    foreach ($rule in $rules) {
        $existing = netsh advfirewall firewall show rule name="$($rule.Name)" 2>$null
        if ($existing -notmatch "Rule Name") {
            $needed += $rule
        }
    }

    if ($needed.Count -eq 0) {
        Write-Host "Firewall rules already exist"
        return 0
    }

    # Build a single command for all rules
    $cmds = $needed | ForEach-Object {
        "netsh advfirewall firewall add rule name='$($_.Name)' dir=in action=allow protocol=TCP localport=$($_.Port)"
    }
    $combined = $cmds -join "; "

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        $proc = Start-Process powershell -Verb RunAs -Wait -PassThru -ArgumentList "-NoProfile -Command `"$combined`""

        if ($proc.ExitCode -ne 0) {
            Write-Host ""
            Write-Host "ERROR: Failed to add firewall rules." -ForegroundColor Red
            Write-Host ""
            return 1
        }
    } else {
        foreach ($cmd in $cmds) { Invoke-Expression $cmd }
    }

    foreach ($rule in $needed) {
        Write-Host "Added firewall rule: $($rule.Name) (TCP port $($rule.Port))"
    }

    return 0
}

function Invoke-CopySshKeys {
    # Remove authorized_keys if it's a directory.
    # Docker creates a directory when mounting a file that doesn't exist - clean it up if this happened.
    if (Test-Path $AuthorizedKeysFile -PathType Container) {
        Remove-Item $AuthorizedKeysFile -Recurse -Force
    }

    $UserSshDir = Join-Path $env:USERPROFILE ".ssh"
    $keys = @()

    # Fetch all public keys the user can authenticate against
    $pubFiles = Get-ChildItem -Path $UserSshDir -Filter "*.pub" -ErrorAction SilentlyContinue

    foreach ($pub in $pubFiles) {
        $keys += Get-Content $pub.FullName
    }

    # Fetch all keys that can be used to authenticate at the user on this machine
    $UserAuthKeysFile = Join-Path $UserSshDir "authorized_keys"

    if (Test-Path $UserAuthKeysFile) {
        $keys += Get-Content $UserAuthKeysFile
    }

    # Exit if there are no keys to copy
    if ($keys.Count -eq 0) {
        Write-Error "No public keys found in $UserSshDir"
        return 1
    }

    # Preserve the picker's key if it exists in the current file
    if (Test-Path $AuthorizedKeysFile) {
        $pickerKeys = Get-Content $AuthorizedKeysFile | Where-Object { $_ -match 'claude-sandbox-picker$' }
        if ($pickerKeys) { $keys += $pickerKeys }
    }

    # Write the extracted keys to the sandbox authorized_keys file
    $keys | Sort-Object -Unique | Set-Content -Path $AuthorizedKeysFile

    # Inform the user of the result
    Write-Host ""
    Write-Host "Wrote $($keys.Count) key(s) to $AuthorizedKeysFile"
    Write-Host ""

    if (-not $pubFiles) {
        Write-Host "WARNING: No SSH key pair found on this machine." -ForegroundColor Yellow
        Write-Host "  You will not be able to connect from this machine without one." -ForegroundColor Yellow
        Write-Host "  Generate a key pair with: ssh-keygen -t ed25519" -ForegroundColor Yellow
        Write-Host ""
    }

    return 0
}

function Invoke-Connect {
    $InstanceName = Get-InstanceName $Environment
    $Port = Get-SshPort $InstanceName
    ssh -o StrictHostKeyChecking=no -p $Port claude@localhost
}

function Stop-Picker {
    $PickerCompose = Join-Path $PSScriptRoot "picker" "compose.yml"
    $env:SANDBOX_AUTHORIZED_KEYS = $AuthorizedKeysFile
    docker compose -f $PickerCompose -p claude-picker down 2>$null
}

function Ensure-Picker {
    $PickerComposeArgs = @("-f", (Join-Path $PSScriptRoot "picker" "compose.yml"))
    if ($SandboxDev) {
        $PickerComposeArgs += @("-f", (Join-Path $PSScriptRoot "picker" "dev.compose.yml"))
    }

    # Ensure authorized keys exist
    if (-not (Test-Path $AuthorizedKeysFile)) {
        New-Item -ItemType File -Force -Path $AuthorizedKeysFile | Out-Null
    }

    $env:SANDBOX_AUTHORIZED_KEYS = $AuthorizedKeysFile
    $env:HOST_HOSTNAME = (hostname)

    $Port = $env:PICKER_SSH_PORT
    if (-not $Port) { $Port = 22000 }

    $running = docker compose @PickerComposeArgs -p claude-picker ps --status running --format "{{.Name}}" 2>$null
    if (-not ($running -match "picker")) {
        docker compose @PickerComposeArgs -p claude-picker up -d --build
        ssh-keygen -R "[localhost]:$Port" 2>$null
    }
}

function Invoke-Start {
    $ctx = Get-ComposeContext

    if (Test-SandboxRunning $ctx.ComposeArgs) {
        Show-ConnectionInfo $ctx.InstanceName $ctx.Port
        return
    }

    Invoke-SandboxBuild $ctx
    Invoke-SandboxUp $ctx
}

function Invoke-Restart {
    $ctx = Get-ComposeContext

    if (Test-SandboxRunning $ctx.ComposeArgs) {
        docker compose @($ctx.ComposeArgs) down
    }

    Invoke-SandboxUp $ctx
}

function Invoke-Rebuild {
    $ctx = Get-ComposeContext

    if (Test-SandboxRunning $ctx.ComposeArgs) {
        docker compose @($ctx.ComposeArgs) down
    }

    Stop-Picker

    Invoke-SandboxBuild $ctx
    Invoke-SandboxUp $ctx
}

function Test-SandboxRunning([string[]]$ComposeArgs) {
    $running = docker compose @ComposeArgs ps --status running --format "{{.Name}}" 2>$null
    $running -match $Environment
}

function Get-ComposeContext {
    $InstanceName = Get-InstanceName $Environment
    $Port = Get-SshPort $InstanceName
    $ComposeArgs = @("-f", (Join-Path $PSScriptRoot "docker-compose.yml"), "-f", (Join-Path $PSScriptRoot "environments" $Environment "compose.yml"))

    if ($SandboxDev) {
        $ComposeArgs += @("-f", (Join-Path $PSScriptRoot "dev.compose.yml"))
    }

    Initialize-ComposeEnvironment $InstanceName $Port

    @{ InstanceName = $InstanceName; Port = $Port; ComposeArgs = $ComposeArgs }
}

function Initialize-ComposeEnvironment([string]$InstanceName, [int]$Port) {
    $env:COMPOSE_PROJECT_NAME = $InstanceName
    $env:SANDBOX_ROOT = $PSScriptRoot
    $env:SANDBOX_ENV = $Environment
    $env:SANDBOX_WORKSPACE = (Split-Path $WorkDir -Leaf)
    $env:DEV_DIR = $WorkDir
    $env:HOME = $env:USERPROFILE
    $env:CLAUDE_SSH_PORT = $Port

    $env:HOST_PLUGINS_DIR = Join-Path (Join-Path $env:USERPROFILE ".claude") "plugins"

    # Per-instance state directory
    $env:CLAUDE_STATE_DIR = Join-Path $SandboxDir $InstanceName
    if (-not (Test-Path $env:CLAUDE_STATE_DIR)) {
        New-Item -ItemType Directory -Force -Path $env:CLAUDE_STATE_DIR | Out-Null
    }

    # SSH authorized keys file — shared across all instances, user-managed
    # Ensure the file exists so Docker mounts a file, not /dev/null
    $env:SANDBOX_AUTHORIZED_KEYS = $AuthorizedKeysFile

    if (Test-Path $env:SANDBOX_AUTHORIZED_KEYS -PathType Container) {
        Remove-Item $env:SANDBOX_AUTHORIZED_KEYS -Recurse -Force
    }

    if (-not (Test-Path $env:SANDBOX_AUTHORIZED_KEYS)) {
        New-Item -ItemType File -Force -Path $env:SANDBOX_AUTHORIZED_KEYS | Out-Null
    }
}

function Invoke-SandboxBuild([hashtable]$ctx) {
    docker compose @($ctx.ComposeArgs) build
    Initialize-StateDirectory
}

function Invoke-SandboxUp([hashtable]$ctx) {
    Ensure-Picker
    docker compose @($ctx.ComposeArgs) up -d
    Wait-ForSshd $ctx.Port
    Show-ConnectionInfo $ctx.InstanceName $ctx.Port
}

function Wait-ForSshd([int]$Port) {
    $ErrorActionPreference = "Continue"

    $retries = 0

    while ($retries -lt 15) {
        $result = ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=1 -p $Port claude@localhost echo ok 2>&1

        if ("$result" -eq "ok") {
            break
        }

        Start-Sleep -Milliseconds 500
        $retries++
    }

    $ErrorActionPreference = "Stop"
}

function Initialize-StateDirectory {
    # Ensure .claude.json exists in state dir
    $ClaudeJson = Join-Path $env:CLAUDE_STATE_DIR ".claude.json"

    if (-not (Test-Path $ClaudeJson)) {
        Set-Content -Path $ClaudeJson -Value "{}"
    }

    # Fix ownership of state directory so container's claude user (UID 1000) can read/write
    docker run --rm -v "${env:CLAUDE_STATE_DIR}:/state" alpine chown -R 1000:1000 /state

    # Remove stale SSH host key for this port
    ssh-keygen -R "[localhost]:$($env:CLAUDE_SSH_PORT)" 2>$null
}

function Show-ConnectionInfo([string]$InstanceName, [int]$Port) {
    $HasAuthorizedKeys = (Get-Item $env:SANDBOX_AUTHORIZED_KEYS).Length -gt 0

    $PickerPort = $env:PICKER_SSH_PORT
    if (-not $PickerPort) { $PickerPort = 22000 }

    Write-Host ""
    Write-Host "[$InstanceName] workspace: $WorkDir ($Environment)"
    Write-Host ""
    Write-Host "  Connect directly to the sandbox:"
    Write-Host "      ssh -p $Port claude@localhost"
    Write-Host ""
    Write-Host "  Connect through the sandbox picker:"
    Write-Host "      ssh -p $PickerPort claude@localhost"
    Write-Host ""

    Show-SshWarnings $HasAuthorizedKeys
}

function Show-SshWarnings([bool]$HasAuthorizedKeys) {
    if (-not $HasAuthorizedKeys) {
        Write-Host "WARNING: No SSH keys configured. You will not be able to connect." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Add public keys to: $AuthorizedKeysFile" -ForegroundColor Yellow
        Write-Host "  Or re-run with -CopySshKeys to import from ~/.ssh" -ForegroundColor Yellow
        Write-Host ""
    }

    $UserSshDir = Join-Path $env:USERPROFILE ".ssh"

    if (-not (Test-Path (Join-Path $UserSshDir "*.pub"))) {
        Write-Host "WARNING: No SSH key pair found on this machine." -ForegroundColor Yellow
        Write-Host "  You will not be able to connect from this machine without one." -ForegroundColor Yellow
        Write-Host "  Generate a key pair with: ssh-keygen -t ed25519" -ForegroundColor Yellow
        Write-Host ""
    }
}

# --- Entry point ---

Main
