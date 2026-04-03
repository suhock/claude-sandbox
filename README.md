# Claude Sandbox

A Docker-based development environment that provides isolated, SSH-accessible workspaces for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Each sandbox runs in its own container with a restrictive network proxy that only allows traffic to Anthropic services, keeping your development environment secure by default.

> **WARNING: Sandboxes are not secured for network exposure.** SSH is configured with empty passwords and passwordless authentication. These instances must never be directly exposed to a network or the public internet. The intended access pattern is to VPN into the network where your development machine resides, SSH into the development machine, and then SSH into the sandbox instance from there (a jump host / ProxyJump configuration). SSH clients like [Termius](https://termius.com/) (Android, iOS, desktop) support this kind of chained connection natively.

## Architecture

```
                                    ┌─────────────────────────────┐
  SSH (port 2200-2999)              │     Claude Container        │
 ─────────────────────────────────► │  Claude Code + tmux + SSH   │
                                    │  /workspace (bind mount)    │
                                    └────────────┬────────────────┘
                                                 │ HTTP/HTTPS
                                                 ▼
                                    ┌─────────────────────────────┐
                                    │     Proxy Container         │
                                    │  Squid (allowlist-only)     │
                                    │  DNSmasq                    │
                                    └────────────┬────────────────┘
                                                 │ HTTPS (443)
                                                 ▼
                                         Anthropic services only
                                         (api.anthropic.com, etc.)
```

Two containers are orchestrated via Docker Compose:

- **Proxy** -- Squid HTTP proxy + DNSmasq DNS server. All outbound traffic from the sandbox is routed through this proxy, which only allows HTTPS connections to Anthropic-owned domains.
- **Claude** -- The development container. Runs SSH, tmux, and Claude Code. Your project directory is bind-mounted at `/workspace`.

## Prerequisites

- **Windows 10/11** with PowerShell 5.0+
- **Docker Desktop** installed and running
- **SSH client** (built-in on modern Windows)

## Installation

1. Clone the repository:

   ```bash
   git clone <repo-url>
   cd claude-sandbox
   ```

2. Run the installer to add the `claude-sandbox` command to your PATH:

   ```powershell
   .\install.ps1
   ```

   This creates wrapper scripts in `~\.bin` and adds that directory to your user PATH.

3. Restart your terminal so the PATH change takes effect.

## Usage

### Launching a sandbox

```powershell
claude-sandbox -Environment <base|php|dotnet> [-DevDir <path>] [-SshPort <port>] [-Rebuild]
```

| Parameter      | Required | Default             | Description                                    |
|----------------|----------|---------------------|------------------------------------------------|
| `-Environment` | Yes      | --                  | Environment type: `dotnet`, `php`, or `base`   |
| `-DevDir`      | No       | Current directory   | Host directory to mount as `/workspace`         |
| `-SshPort`     | No       | Auto-assigned       | SSH port on the host (range 2200-2999)          |
| `-Rebuild`     | No       | `false`             | Force rebuild of the container image            |

Examples:

```powershell
# Rebuild a .NET sandbox with a custom SSH port
claude-sandbox -Environment dotnet -DevDir . -SshPort 2345 -Rebuild

# Launch a PHP sandbox for a specific project
claude-sandbox -Environment php -DevDir D:\projects\my-php-app

# Launch a Node.js sandbox for the current directory
claude-sandbox -Environment base
```

You can also run directly from the repository root without installing:

```powershell
.\run.ps1 -Environment base -DevDir D:\projects\myapp
```

### Connecting via SSH

Once the sandbox is running, the script outputs the SSH command:

```bash
ssh -p <port> claude@localhost
```

No password is required -- your host SSH keys (`~/.ssh/authorized_keys`) are automatically imported into the container.

### Working with tmux sessions

When you SSH in, an interactive session picker is displayed:

- **N** -- Create a new Claude Code session (launches the Claude REPL)
- **S** -- Create a new shell session
- **0-9** -- Attach to an existing session
- **Q** -- Quit (disconnect)

Sessions persist across SSH disconnections, so you can reconnect and pick up where you left off. Each session gets a color-coded tmux status bar showing the workspace name and environment.

### Managing instances

Each combination of workspace path + environment name produces a **stable instance**:

- The instance name is derived from a hash, so running the same command again reconnects to the existing container.
- Per-instance state (Claude config, SSH host keys) is stored in `~\.claude-sandbox\<instance-name>\`.
- Multiple sandboxes can run concurrently on different ports.

To fully remove an instance, stop the container and delete its state directory:

```powershell
docker compose -p <instance-name> down
Remove-Item -Recurse ~\.claude-sandbox\<instance-name>
```

### Plugins

Plugins are supported by syncing them from your host machine's Claude Code installation. To use plugins in a sandbox:

1. Install the plugins on your **host** (non-sandboxed) Claude Code instance first.
2. When a sandbox starts, the entrypoint automatically copies plugin data from `~/.claude/plugins` (mounted read-only) into the container.
3. Windows paths in plugin metadata are translated to Linux paths automatically.

No additional configuration is needed -- any plugins you have installed on the host will be available inside the sandbox.

## Environments

### .NET 10.0

```powershell
claude-sandbox -Environment dotnet
```

- **Image:** `mcr.microsoft.com/dotnet/sdk:10.0`
- `csharp-ls` language server installed
- Host NuGet cache (`~/.nuget/packages`) is mounted for persistence

### PHP 8.4

```powershell
claude-sandbox -Environment php
```

- **Image:** `php:8.4-cli`
- Extensions: `zip`, `intl`, `mbstring`
- Composer installed globally
- Host Composer cache (`~/.composer/cache`) is mounted for persistence

### Base (Node.js 22)

```powershell
claude-sandbox -Environment base
```

- **Image:** `node:22-bookworm-slim`
- Node.js v22 pre-installed
- No additional setup beyond the shared tooling

## Adding a new environment

1. Create a directory under `environments/`:

   ```
   environments/my-env/
   ├── compose.yml          # Required: Docker Compose overrides
   ├── setup-root.sh        # Optional: runs as root during image build
   └── setup-user.sh        # Optional: runs as claude user during image build
   ```

2. In `compose.yml`, override the base image and add any volumes:

   ```yaml
   services:
     claude:
       build:
         args:
           BASE_IMAGE: your-base-image:tag
       volumes:
         - "host-cache-path:/home/claude/.cache/tool"
   ```

3. Use `setup-root.sh` for system packages (runs as root) and `setup-user.sh` for user-level tools (runs as the `claude` user).

4. Launch it:

   ```powershell
   claude-sandbox -Environment my-env
   ```

## Network security

The proxy container enforces a strict allowlist. Only HTTPS (port 443) connections to the following domains are permitted:

| Domain                    | Purpose                   |
|---------------------------|---------------------------|
| `api.anthropic.com`       | Claude API                |
| `platform.claude.com`     | Claude platform           |
| `claude.ai`               | Claude web interface      |
| `statsig.anthropic.com`   | Analytics                 |
| `downloads.claude.ai`     | Asset downloads           |
| `code.claude.com`         | Claude Code resources     |

All other outbound traffic is denied. To allow additional domains, edit `proxy/squid.conf` and add entries to the `allowed_domains` ACL.

## Project structure

```
claude-sandbox/
├── docker-compose.yml        # Main orchestration (proxy + claude services)
├── run.ps1                   # Entry point for launching sandboxes
├── install.ps1               # CLI installation script
├── proxy/
│   ├── Dockerfile            # Alpine-based proxy image
│   ├── squid.conf            # HTTP proxy allowlist rules
│   ├── dnsmasq.conf          # DNS configuration
│   └── start.sh              # Proxy container entry point
├── shared/
│   ├── Dockerfile            # Base image for all sandbox environments
│   ├── setup.sh              # Two-phase setup (root + user)
│   ├── entrypoint.sh         # Container startup (plugin sync, SSH, etc.)
│   └── tmux-picker.sh        # Interactive tmux session picker
└── environments/
    ├── dotnet/               # .NET 10.0 environment
    │   ├── compose.yml
    │   └── setup-user.sh
    ├── php/                  # PHP 8.4 environment
    │   ├── compose.yml
    │   └── setup-root.sh
    └── base/                 # Node.js 22 environment
        └── compose.yml
```

## Troubleshooting

### Container fails to start

Make sure Docker Desktop is running. Check logs with:

```powershell
docker compose -p <instance-name> logs
```

### SSH connection refused

The sandbox waits for sshd to be ready before returning, but if it times out:

1. Verify the container is running: `docker ps`
2. Check that the correct port is being used (shown in the launch output)
3. Remove stale host keys: `ssh-keygen -R "[localhost]:<port>"`

### Proxy blocking required traffic

If Claude Code can't reach Anthropic services, check the proxy logs:

```powershell
docker compose -p <instance-name> logs proxy
```

To allow additional domains, add them to the `allowed_domains` ACL in `proxy/squid.conf` and rebuild with `-Rebuild`.

### Rebuilding from scratch

Use the `-Rebuild` flag to force a fresh image build:

```powershell
claude-sandbox -Environment base -Rebuild
```

This rebuilds the Docker image from scratch without using the cache.
