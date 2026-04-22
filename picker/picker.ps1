# Interactive sandbox picker — discovers running/stopped sandboxes, starts and connects.
# Native Windows/PowerShell counterpart to picker.sh.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Force UTF-8 output so box-drawing glyphs render (default OEM code page emits ?)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Target host for sandbox SSH. Mirrors picker.sh — defaults to localhost on a
# bare host; override via PICKER_SSH_HOST to point elsewhere.
$SSH_HOST = if ($env:PICKER_SSH_HOST) { $env:PICKER_SSH_HOST } else { "localhost" }

# Color palette (matches picker.sh)
$C_RESET     = "`e[0m"
$C_BOLD      = "`e[1m"
$C_PRIMARY   = "`e[38;5;223m"  # pale yellow
$C_SECONDARY = "`e[38;5;174m"  # claude code pink
$C_TERTIARY  = "`e[38;5;246m"  # neutral gray
$C_STOPPED   = "`e[38;5;240m"  # dark gray

$script:Sandboxes = @()
$script:HostName  = [System.Net.Dns]::GetHostName()

function Write-Line([string]$Text) {
    # Write with clear-to-end-of-line
    [Console]::Write("$Text`e[K`n")
}

function Get-Sandboxes {
    $list = New-Object System.Collections.Generic.List[object]

    # Docker format templates — use tab as the field separator. Built by concatenation
    # so the `t escape is interpreted by PowerShell (single-quoted strings wouldn't).
    $TAB = "`t"
    $runningFmt = '{{.Names}}' + $TAB + '{{.Ports}}' + $TAB + '{{.Label "sandbox.env"}}' + $TAB + '{{.Label "sandbox.workspace"}}' + $TAB + '{{.Label "com.docker.compose.project"}}'
    $stoppedFmt = '{{.Names}}' + $TAB + '{{.Label "sandbox.env"}}' + $TAB + '{{.Label "sandbox.workspace"}}' + $TAB + '{{.Label "com.docker.compose.project"}}'

    # Running sandboxes (gateway containers have the labels + port mapping)
    $runningOut = @(docker ps --filter 'label=sandbox.env' --format $runningFmt 2>$null)

    foreach ($line in $runningOut) {
        if (-not $line) {
            continue
        }

        $parts = $line -split $TAB

        if ($parts.Count -lt 5) {
            continue
        }

        # Extract host port from Ports like "0.0.0.0:22001->22/tcp, ..."
        if ($parts[1] -notmatch ':(\d+)->22/tcp') {
            continue
        }

        $port = [int]$Matches[1]

        $list.Add([pscustomobject]@{
            Name      = $parts[0]
            Project   = $parts[4]
            Port      = $port
            Env       = $parts[2]
            Workspace = $parts[3]
            Running   = $true
        })
    }

    # Stopped sandboxes — skip projects we already have running
    $runningProjects = @($list | ForEach-Object { $_.Project })

    $stoppedOut = @(docker ps -a --filter 'label=sandbox.env' --filter 'status=exited' --format $stoppedFmt 2>$null)

    foreach ($line in $stoppedOut) {
        if (-not $line) {
            continue
        }

        $parts = $line -split $TAB

        if ($parts.Count -lt 4) {
            continue
        }

        $project = $parts[3]
        if ($runningProjects -contains $project) { continue }

        $list.Add([pscustomobject]@{
            Name      = $parts[0]
            Project   = $project
            Port      = 0
            Env       = $parts[1]
            Workspace = $parts[2]
            Running   = $false
        })
    }

    $script:Sandboxes = @($list | Sort-Object Workspace, Env)
}

function Start-Sandbox([string]$Project) {
    # List all containers in the project, start gateway first
    $TAB = "`t"
    $fmt = '{{.Names}}' + $TAB + '{{.Label "com.docker.compose.service"}}'
    $containersOut = @(docker ps -a --filter "label=com.docker.compose.project=$Project" --format $fmt 2>$null)

    $gateway = $null
    $others  = @()

    foreach ($line in $containersOut) {
        if (-not $line) {
            continue
        }

        $parts = $line -split $TAB

        if ($parts.Count -lt 2) {
            continue
        }

        if ($parts[1] -eq "gateway") {
            $gateway = $parts[0]
        }
        else {
            $others += $parts[0]
        }
    }

    if ($gateway) {
        docker start $gateway *>$null
    }
    
    foreach ($c in $others) {
        docker start $c *>$null
    }

    # Resolve SSH port from gateway container
    $portOut = docker port "$Project-gateway-1" 22 2>$null

    if (-not $portOut) {
        return 0
    }

    if ($portOut -notmatch ':(\d+)') {
        return 0
    }

    $port = [int]$Matches[1]

    # Wait for SSH to answer
    for ($i = 0; $i -lt 30; $i++) {
        $result = ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL `
            -o ConnectTimeout=1 -o BatchMode=yes -p $port claude@$SSH_HOST echo ok 2>$null

        if ("$result".Trim() -eq "ok") {
            return $port
        }
        
        Start-Sleep -Seconds 1
    }

    return 0
}

function Show-Menu {
    # Terminal title + cursor home + hide cursor
    [Console]::Write("`e]0;🟨 $script:HostName`a")
    [Console]::Write("`e[?25l`e[H")

    Write-Line ""
    Write-Line "${C_PRIMARY} ▖▖▖ ▟▙ ▗▗▗ ${C_RESET}"
    Write-Line "${C_PRIMARY} ██▙▟▛▜▙▟██ ${C_RESET} ${C_BOLD}Claude Sandbox${C_RESET}"

    $cols = [Console]::WindowWidth
    $header = "${C_TERTIARY}…${C_PRIMARY}████  ████${C_TERTIARY}… $script:HostName "
    $fill = $cols - 14 - $script:HostName.Length

    if ($fill -gt 0) {
        $header += ('…' * $fill)
    }

    Write-Line ($header + $C_RESET)
    Write-Line ""

    if ($script:Sandboxes.Count -eq 0) {
        Write-Line "  ${C_TERTIARY}No sandboxes found${C_RESET}"
    } else {
        Write-Line "  ${C_TERTIARY}Sandbox Instances${C_RESET}"
        Write-Line ""

        for ($i = 0; $i -lt $script:Sandboxes.Count; $i++) {
            $sb  = $script:Sandboxes[$i]
            $key = (($i + 1) % 10)
            $env = if ($sb.Env) { $sb.Env } else { "unknown" }
            $ws  = if ($sb.Workspace) { $sb.Workspace } else { "workspace" }

            if ($sb.Running) {
                Write-Line "  ${C_PRIMARY}${key}${C_RESET}  ${C_SECONDARY}${ws} (${env})${C_RESET} ${C_TERTIARY}:$($sb.Port)${C_RESET}"
            } else {
                Write-Line "  ${C_PRIMARY}${key}${C_RESET}  ${C_STOPPED}${ws} (${env})${C_RESET}"
            }
        }
    }

    Write-Line ""
    Write-Line "  ${C_PRIMARY}Q${C_RESET}  Quit"
    Write-Line ""

    # Prompt + clear to end of screen + show cursor
    [Console]::Write("  ${C_TERTIARY}>${C_RESET} `e[J`e[?25h")
}

# NOTE: ssh is invoked inline at the call sites (not from a function) so that
# PowerShell doesn't capture its stdout. Capturing breaks ConPTY: ssh detects a
# non-TTY stdout, enters a degraded mode, and the remote tmux UI never paints
# even though keystrokes still flow.

function Get-MenuState {
    # Fingerprint of names + running flags — used to skip redraws when nothing changed
    ($script:Sandboxes | ForEach-Object { "$($_.Name):$($_.Running)" }) -join "`n"
}

# --- Main loop ---

Clear-Host
[Console]::TreatControlCAsInput = $false

$prevCursor = [Console]::CursorVisible

try {
    $redraw           = $true
    $lastDraw         = [datetime]::MinValue
    $refreshInterval  = [timespan]::FromSeconds(2)
    $menuState        = ""
    $lastCols         = [Console]::WindowWidth

    while ($true) {
        # Detect terminal resize
        if ([Console]::WindowWidth -ne $lastCols) {
            $lastCols = [Console]::WindowWidth
            $redraw = $true
        }

        if ($redraw -or (([datetime]::Now - $lastDraw) -ge $refreshInterval)) {
            $prevState = $menuState
            Get-Sandboxes
            $menuState = Get-MenuState

            if ($redraw -or $menuState -ne $prevState) {
                Show-Menu
            }

            $redraw   = $false
            $lastDraw = [datetime]::Now
        }

        # Poll for keypress
        if (-not [Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 250
            continue
        }

        $key = [Console]::ReadKey($true)
        $ch  = $key.KeyChar

        if ($ch -eq 'Q' -or $ch -eq 'q') {
            [Console]::Write("$ch`n")
            break
        }

        # Only digits drive the menu; ignore arrows and other keys
        if ($ch -notmatch '^\d$') {
            continue
        }

        $idx = (([int][string]$ch) + 9) % 10

        if ($idx -ge $script:Sandboxes.Count) {
            continue
        }

        $sb = $script:Sandboxes[$idx]
        $rc = 0

        if ($sb.Running) {
            [Console]::Write("`n`n  ${C_TERTIARY}Connecting...${C_RESET}")
            ssh -o StrictHostKeyChecking=no -p $sb.Port claude@$SSH_HOST
            $rc = $LASTEXITCODE
        } else {
            [Console]::Write("`n`n  ${C_TERTIARY}Starting...${C_RESET}")
            $port = Start-Sandbox $sb.Project
            
            if ($port -gt 0) {
                ssh -o StrictHostKeyChecking=no -p $port claude@$SSH_HOST
                $rc = $LASTEXITCODE
            } else {
                $rc = 1
            }
        }

        if ($rc -ne 0) {
            [Console]::Write("`n  ${C_SECONDARY}Press any key to continue...${C_RESET}")
            [Console]::ReadKey($true) | Out-Null
        }

        $redraw = $true
    }
}
finally {
    [Console]::CursorVisible = $prevCursor
    [Console]::Write("`e[?25h")
}
