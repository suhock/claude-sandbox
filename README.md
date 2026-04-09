# Claude Sandbox

A Docker-based development environment for Windows and Linux that provides isolated, SSH-accessible workspaces for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Each sandbox runs in its own container with a restrictive network gateway that only allows traffic to Anthropic services and explicitly whitelisted services, keeping your development environment secure by default.

## Key Features

### Security
- **File system** — Only your project directory is bind-mounted into the container. Claude can read and write files there but has no access to the rest of your host filesystem.
- **Networking** — All outbound traffic is routed through an iptables gateway with DNS-based filtering. Only Anthropic domains necessary for Claude Code and specifically specified domains whitelisted for the development environment are allowed.

### Convenience
- **Remote access** — Connect from anywhere with your phone or other device.
- **Session management** - Uses tmux for session management, so reconnect and resume where you left off.
- **Sandbox picker** — A single SSH entry point that presents all available sandboxes.

### **Flexibility**
- **Multiple environments** — Pre-built configurations for working with .NET, Node.js, and PHP. Add new ones with a minimal `compose.yml` and a couple setup scripts.


> **NOTE:** These instances should not be directly exposed to the public internet. See [Remote Access](#remote-access) for connecting from other devices.

## Architecture

```
  SSH (port 22000)        ┌─────────────────────────────┐
  ──────────────────────► │  Picker                     │
                          └────────────┬────────────────┘
                                   SSH │
                                       ▼
  SSH (port 22001-22999)  ┌────────────────────────────┐
  ──────────────────────► │  Gateway                   │
                          │  (iptables + DNSmasq)      │
                          └───┬─────────────────────┬──┘
                          SSH │         ▲     HTTPS │
                              ▼   HTTPS │           ▼
                          ┌─────────────┴──┐    Whitelisted
                          │  Claude Code   │    services only
                          │  tmux          │
                          └────────────────┘
```

Each project has two containers:

- **Gateway** -- iptables-based network gateway + DNSmasq DNS server. All outbound traffic from the sandbox is routed through this gateway, which only allows HTTPS connections to Anthropic-owned domains by default.
- **Claude** -- The development container. Runs SSH, tmux, and Claude Code. Your project directory is bind-mounted at `/workspace`.

Additionally, there is a lightweight management container that discovers all running and stopped sandboxes via the Docker socket. It provides a single SSH entry point (port 22000) with an interactive menu for selecting and connecting to sandboxes. It's started automatically alongside any sandbox.

## Prerequisites

- **Windows 10/11** with PowerShell 5.0+
- **Docker Desktop** installed and running
- **SSH client** (built-in on modern Windows)
- **SSH key pair** for authentication (see [SSH Authentication](#ssh-authentication))

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

   This creates wrapper scripts in `~\.local\bin` and adds that directory to your user PATH.

3. Restart your terminal so the PATH change takes effect.

## Usage

### Launching a sandbox

```powershell
claude-sandbox [-Start] [-Environment <name>] [-WorkDir <path>] [-SshPort <port>]
claude-sandbox -Restart [-Environment <name>] [-SshPort <port>]
claude-sandbox -Rebuild [-Environment <name>] [-WorkDir <path>] [-SshPort <port>]
claude-sandbox -Connect [-Environment <name>]
claude-sandbox -Picker
claude-sandbox -CopySshKeys
claude-sandbox -AddFirewallRule [-Environment <name>]
```

**Commands** (mutually exclusive, default: `-Start`):

| Command            | Description                                           |
|--------------------|-------------------------------------------------------|
| `-Start`           | Start the sandbox (build if necessary)                |
| `-Restart`         | Stop and restart the container                        |
| `-Rebuild`         | Force rebuild the container image                     |
| `-Connect`         | SSH into the container                                |
| `-Picker`          | SSH into the sandbox picker                           |
| `-CopySshKeys`     | Import SSH keys from `~/.ssh` (see [below](#ssh-authentication)) |
| `-AddFirewallRule` | Open SSH ports (sandbox + picker) in Windows Firewall (requests elevation) |

**Options:**

| Option          | Description                                           |
|-----------------|-------------------------------------------------------|
| `-Environment`  | Runtime environment (inferred if only one exists for directory) |
| `-WorkDir`       | Workspace directory (default: current directory)       |
| `-SshPort`      | SSH port on the host (default: auto-assigned, range 22001-22999) |

If you've previously launched a sandbox for a directory and there is only one environment associated with it, you can omit `-Environment` and it will be inferred automatically:

If multiple environments have been used with the same directory, you'll be prompted to specify which one.

Examples:

```powershell
cd D:\dev\my-dotnet-solution

# Build a .NET sandbox
claude-sandbox -Environment dotnet

# Import public SSH keys from ~/.ssh
claude-sandbox -CopySshKeys

# Connect to a running sandbox
claude-sandbox -Connect

# Open Windows Firewall for remote access (requests elevation)
claude-sandbox -AddFirewallRule

# Restart a running sandbox
claude-sandbox -Restart
```

### SSH authentication

Password authentication is disabled. All sandbox containers share a single authorized keys file at `~\.claude-sandbox\authorized_keys`. Add one public key per line. Changes take effect immediately on the next SSH connection -- no container restart required.

**Option 1: Manual setup**

Create the file and add your public key(s):

```powershell
mkdir ~\.claude-sandbox -Force
copy ~/.ssh/id_ed25519.pub ~/.claude-sandbox/authorized_keys
```

If you don't have an SSH key pair, generate one first:

```powershell
ssh-keygen -t ed25519
```

**Option 2: Import from `~/.ssh`**

The `-CopySshKeys` flag collects all public keys (`~/.ssh/*.pub`) and authorized keys (`~/.ssh/authorized_keys`) from your host into `~\.claude-sandbox\authorized_keys`:

```powershell
claude-sandbox -Environment base -CopySshKeys
```

This can be run at any time, including against already-running sandboxes, to refresh the keys.

### Connecting via SSH

Once the sandbox is running, the script outputs two connection options:

```
  Connect directly to the sandbox:
      ssh -p <port> claude@localhost

  Connect through the sandbox picker:
      ssh -p 22000 claude@localhost
```

The **sandbox picker** is started automatically alongside any sandbox. It listens on port 22000 and presents an interactive menu listing all running and stopped sandboxes. Selecting a stopped sandbox will start it automatically. This is especially useful for remote access, where you only need to remember one port.

### Remote access

To connect from another device (phone, tablet, laptop), first open the firewall:

```powershell
claude-sandbox -Environment dotnet -AddFirewallRule
```

This opens ports for both the sandbox and the picker (port 22000) in Windows Firewall.

**Via the picker (recommended)** -- Connect to the picker from any device and select a sandbox from the menu:

```bash
ssh -p 22000 claude@<dev-machine-ip>
```

**Direct connection** -- Connect to a specific sandbox by port:

```bash
ssh -p <port> claude@<dev-machine-ip>
```

**SSH jump host** -- If Docker ports are not directly reachable, chain through your dev machine using `ProxyJump`. This requires the OpenSSH server to be running on your Windows machine. To enable it (from an elevated PowerShell prompt):

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service sshd -StartupType Automatic
```

On the connecting device, add to `~/.ssh/config`:

```
Host sandbox
    HostName localhost
    Port 22000
    User claude
    ProxyJump <user>@<dev-machine-ip>
```

Then connect with `ssh sandbox`.

### Working with tmux

When you SSH in, you're automatically attached to a tmux session. On first connect, a Claude Code window is created. Windows persist across SSH disconnections, so you can reconnect and pick up where you left off.

**Creating new windows:**

| Method | Claude Code | Bash |
|--------|------------|------|
| Keyboard | `Ctrl-b c` | `Ctrl-b b` |
| Status bar | Click `c:+Claude` | Click `b:+Bash` |

**Switching windows:** Click a window tab in the status bar, or use `Ctrl-b <number>`.

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

> **Why sync instead of install natively?** Most marketplace plugins are hosted on GitHub, which is blocked by the gateway's network rules by default. Copying pre-installed plugins from the host avoids the need to whitelist `github.com`.

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

The gateway container routes all traffic from the sandbox through iptables. Only connections to allowed domains are forwarded; everything else is dropped.

Base allowed domains are defined in `gateway/allowed-domains.conf`. To allow additional domains for a specific environment, create an `allowed-domains.conf` in the environment's folder and mount it in `compose.yml`:

```
environments/dotnet/allowed-domains.conf:
  api.nuget.org
  globalcdn.nuget.org
```

```yaml
services:
  gateway:
    volumes:
      - ${SANDBOX_ROOT}/environments/dotnet/allowed-domains.conf:/etc/gateway/allowed-domains.d/env.conf:ro
```

To allow additional domains globally, add them to `gateway/allowed-domains.conf`.

> **Warning:** Each domain you add expands the attack surface of the sandbox. An AI agent with network access could exfiltrate code, secrets, or conversation context to any allowed host. Only allow domains you trust and that the environment genuinely needs. Avoid broad wildcards or general-purpose hosts (e.g. `pastebin.com`, `github.com`) unless you fully understand the risk.

## Project structure

```
claude-sandbox/
├── docker-compose.yml        # Main orchestration (gateway + claude services)
├── dev.compose.yml           # Dev overrides (bind-mounts runtime scripts)
├── run.ps1                   # Entry point for launching sandboxes
├── install.ps1               # CLI installation script
├── gateway/
│   ├── Dockerfile            # Alpine-based gateway image
│   ├── dnsmasq.conf          # DNS configuration
│   ├── allowed-domains.conf  # Base domain allowlist
│   └── start.sh              # Gateway container entry point
├── shared/
│   ├── Dockerfile            # Base image for all sandbox environments
│   ├── setup-root.sh         # Root-level setup (packages, sshd, user creation)
│   ├── setup-user.sh         # User-level setup (bashrc, Claude Code, tmux)
│   ├── config/
│   │   ├── tmux.conf         # Tmux configuration (status bar, key bindings)
│   │   └── bashrc.append     # Appended to ~/.bashrc at build time
│   └── runtime/
│       ├── init.sh           # Container init (networking, drops to claude user)
│       ├── entrypoint.sh     # Container startup (plugin sync, SSH, etc.)
│       ├── tmux-picker.sh    # Tmux session attach/create on SSH connect
│       └── new-window.sh     # Creates new tmux windows (used by status bar buttons)
├── picker/
│   ├── Dockerfile            # Alpine-based picker image
│   ├── compose.yml           # Picker container orchestration
│   ├── dev.compose.yml       # Dev overrides for picker
│   ├── picker.sh             # Interactive sandbox discovery and menu
│   └── entrypoint.sh         # Injects picker SSH key into authorized_keys
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

## Developing the sandbox

When working on the sandbox's own runtime scripts, use the hidden `-SandboxDev` flag to bind-mount them into the containers instead of using the copies baked into the images. This lets you edit scripts on the host and see changes immediately on the next connection or restart, without rebuilding.

```powershell
claude-sandbox -Environment base -SandboxDev
```

This applies dev overrides to both the sandbox (`dev.compose.yml`) and the picker (`picker/dev.compose.yml`). Use `-Rebuild` to force a full rebuild of both.

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

### SSH "permission denied"

Verify that `~\.claude-sandbox\authorized_keys` exists and contains your public key. You can re-import keys from `~/.ssh` at any time:

```powershell
claude-sandbox -CopySshKeys
```

### Gateway blocking required traffic

If Claude Code can't reach Anthropic services, check the gateway logs:

```powershell
docker compose -p <instance-name> logs gateway
```

To allow additional domains for a specific environment, add an `allowed-domains.conf` to the environment's folder and mount it in its `compose.yml`. To allow them globally, add them to `gateway/allowed-domains.conf`. Either way, rebuild with `-Rebuild`.

### Rebuilding from scratch

Use the `-Rebuild` flag to force a fresh image build:

```powershell
claude-sandbox -Environment base -Rebuild
```

This rebuilds the Docker image from scratch without using the cache.
