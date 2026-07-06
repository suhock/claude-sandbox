# Interactive sandbox picker — discovers running/stopped sandboxes, starts and connects.
# Native Windows/PowerShell counterpart to picker.sh.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Force legacy native-arg passing so \"-escaping in docker format strings works
# the same way on PowerShell 5.1 and PowerShell 7.3+ (7.3+ would otherwise use
# Standard/Windows mode and treat the backslashes as literal). Harmless no-op on 5.1.
$PSNativeCommandArgumentPassing = 'Legacy'

# Force UTF-8 output so box-drawing glyphs render (default OEM code page emits ?)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Target host for sandbox SSH. Mirrors picker.sh — defaults to localhost on a
# bare host; override via PICKER_SSH_HOST to point elsewhere.
$SSH_HOST = if ($env:PICKER_SSH_HOST) { $env:PICKER_SSH_HOST } else { "localhost" }

# ESC literal — Windows PowerShell 5.1 doesn't understand `e, so build it explicitly.
$ESC = [char]0x1B

# Color palette (matches picker.sh)
$C_RESET     = "${ESC}[0m"
$C_BOLD      = "${ESC}[1m"
$C_PRIMARY   = "${ESC}[38;5;223m"  # pale yellow
$C_SECONDARY = "${ESC}[38;5;174m"  # claude code pink
$C_TERTIARY  = "${ESC}[38;5;246m"  # neutral gray
$C_STOPPED   = "${ESC}[38;5;240m"  # dark gray

$script:Sandboxes = @()
$script:HostName  = [System.Net.Dns]::GetHostName()

function Write-Line([string]$Text) {
    # Write with clear-to-end-of-line
    [Console]::Write("$Text${ESC}[K`n")
}

# Alternate screen buffer — keeps the picker's menu out of the client's
# scrollback. Drop to the normal screen around nested SSH calls so connection
# output and errors accumulate there and can be reviewed after the fact.
function Enter-Alt { [Console]::Write("${ESC}[?1049h") }
function Exit-Alt  { [Console]::Write("${ESC}[?1049l") }

function Get-Sandboxes {
    $list = New-Object System.Collections.Generic.List[object]

    # Docker format templates — use tab as the field separator. Built by concatenation
    # so the `t escape is interpreted by PowerShell (single-quoted strings wouldn't).
    # Inner quotes are \"-escaped so Windows PowerShell 5.1 doesn't strip them when
    # it builds the native command line (the exe's CRT parses \" back to ").
    $TAB = "`t"
    $runningFmt = '{{.Names}}' + $TAB + '{{.Ports}}' + $TAB + '{{.Label \"sandbox.env\"}}' + $TAB + '{{.Label \"sandbox.workspace\"}}' + $TAB + '{{.Label \"com.docker.compose.project\"}}'
    $stoppedFmt = '{{.Names}}' + $TAB + '{{.Label \"sandbox.env\"}}' + $TAB + '{{.Label \"sandbox.workspace\"}}' + $TAB + '{{.Label \"com.docker.compose.project\"}}'

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
    $fmt = '{{.Names}}' + $TAB + '{{.Label \"com.docker.compose.service\"}}'
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

    # Resolve SSH port from gateway container. `docker port` may emit both an
    # IPv4 and an IPv6 mapping — take the first line, which is sufficient.
    $portOut = @(docker port "$Project-gateway-1" 22 2>$null) | Select-Object -First 1

    if (-not $portOut -or $portOut -notmatch ':(\d+)') {
        return 0
    }

    $port = [int]$Matches[1]

    # Wait for sshd to actually be serving. A plain TCP connect is not enough
    # on Docker Desktop: the host-side port proxy accepts connections the
    # moment Docker publishes the port, so the probe succeeds well before
    # the gateway's socat (and the claude container's sshd) are up. Instead,
    # read the first bytes from the socket and confirm they are an SSH banner
    # ("SSH-..."). Only then is the sandbox actually ready to take logins.
    for ($i = 0; $i -lt 60; $i++) {
        if (Test-SshReady $SSH_HOST $port 1000) {
            return $port
        }

        Start-Sleep -Milliseconds 500
    }

    return 0
}

function Test-SshReady([string]$Target, [int]$Port, [int]$TimeoutMs) {
    $tcp = $null
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $task = $tcp.ConnectAsync($Target, $Port)

        if (-not ($task.Wait($TimeoutMs) -and $tcp.Connected)) {
            return $false
        }

        $stream = $tcp.GetStream()
        $stream.ReadTimeout = $TimeoutMs
        $buf = [byte[]]::new(4)
        $read = $stream.Read($buf, 0, 4)

        if ($read -lt 4) {
            return $false
        }

        return ([System.Text.Encoding]::ASCII.GetString($buf, 0, 4) -eq 'SSH-')
    } catch {
        # Connection refused, RST after handshake, read timeout — keep retrying
        return $false
    } finally {
        if ($tcp) { $tcp.Dispose() }
    }
}

function Show-Menu {
    # Terminal title + cursor home + hide cursor
    [Console]::Write("${ESC}]0;🟨 $script:HostName`a")
    [Console]::Write("${ESC}[?25l${ESC}[H")

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
    [Console]::Write("  ${C_TERTIARY}>${C_RESET} ${ESC}[J${ESC}[?25h")
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

[Console]::TreatControlCAsInput = $false

$prevCursor = [Console]::CursorVisible

Enter-Alt

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

        # Drop to the normal screen so connection output lands in scrollback
        Exit-Alt

        if ($sb.Running) {
            [Console]::Write("  ${C_TERTIARY}Connecting...${C_RESET}`n")
            ssh -o StrictHostKeyChecking=no -p $sb.Port claude@$SSH_HOST
            $rc = $LASTEXITCODE
        } else {
            [Console]::Write("  ${C_TERTIARY}Starting...${C_RESET}`n")
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

        Enter-Alt
        $redraw = $true
    }
}
finally {
    [Console]::CursorVisible = $prevCursor
    [Console]::Write("${ESC}[?25h")
    Exit-Alt
}
