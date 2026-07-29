# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker-based isolated development environments for Claude Code on Windows. Each sandbox runs in a two-container setup (gateway + claude) with network-level security that only allows traffic to Anthropic services. A picker container provides a single SSH entry point for discovering and managing sandboxes.

## Build & Run

```powershell
# Install CLI (creates claude-sandbox command, adds to PATH)
.\install.ps1

# Launch a sandbox
claude-sandbox -Environment base -WorkDir D:\dev\myapp

# Development mode (bind-mounts runtime scripts for live iteration)
claude-sandbox -Environment base -SandboxDev

# View logs
docker compose -p <instance-name> logs gateway
```

There are no tests or linters in this project.

## Architecture

**Three container types, two compose files:**

- **Gateway** (`gateway/`) — Alpine. Runs dnsmasq (DNS filtering via ipset) + socat (SSH forwarding) + iptables (traffic filtering). Only allows HTTPS to domains listed in `allowed-domains.conf` files. Sits on two Docker networks: `claude-net` (internal) and `default` (internet access).
- **Claude** (`shared/`) — Debian-based (varies by environment). Development sandbox with SSH, tmux, Claude Code. Only on `claude-net`; all traffic routed through gateway (resolved via Docker DNS at container init).
- **Picker** (`picker/`) — Alpine. Separate compose file (`picker/compose.yml`). Mounts Docker socket to discover sandboxes via labels. Runs on host port 22000. The picker shell script (`picker.sh`) is the login shell for SSH sessions.

**Container startup chain:** `init.sh` (root: resolves gateway via Docker DNS, sets routes and DNS, drops NET_ADMIN via capsh) → `entrypoint.sh` (claude user: syncs plugins, kicks off a background `claude update`, starts sshd) → SSH login triggers `tmux-picker.sh` via bashrc.

**Networking:** Docker assigns subnets and IPs automatically. The claude container's `init.sh` resolves the gateway via Docker DNS, then sets it as the default route and DNS server. Instance names are derived from SHA256(WorkDir:Environment). SSH ports are allocated from 22001-22999 on first launch and persisted in the instance's state directory (`~/.claude-sandbox/<instance-name>/port`).

## Key Design Decisions

- **PID 1 matters:** The claude container runs sshd in foreground (`-D -e`) as the main process so it reaps its own children. The gateway uses `init: true` (tini) since it runs two processes (dnsmasq + socat), with a supervision loop that exits if either dies.
- **DNS-based filtering:** dnsmasq resolves allowed domains into an ipset; iptables FORWARD rules match against that ipset. This avoids hardcoding IPs. dnsmasq listens on `0.0.0.0` so it serves the claude container without interfering with Docker's internal DNS at `127.0.0.11` in the gateway container itself.
- **SSH auth via AuthorizedKeysCommand:** Keys are read from a host-mounted file on every login, so key changes don't require container restarts. The picker injects its own key at startup for inter-container SSH.
- **Plugin sync:** Host plugins are mounted read-only; entrypoint copies them into the writable state dir and converts Windows paths to Linux paths in metadata JSON files. The entrypoint also seeds any environment-provided Claude Code skills/LSP plugins staged at `/opt/claude-skills` into `~/.claude/skills` — this must happen at runtime because `~/.claude` is a bind-mounted volume that shadows image contents. The php env uses this to register `phpactor` with Claude Code's built-in LSP tool via a skills-directory plugin.
- **Persistent home volume:** `/home/claude` is a per-instance named volume (`claude-<instance>_claude-home`, auto-scoped by the compose project name). It seeds from the image on first creation — capturing the baked Claude install (`~/.local`) and env tooling — and survives `-Restart`/`-Rebuild`, so Claude can be upgraded in place without a rebuild — the entrypoint attempts `claude update` on every start (backgrounded so it can't delay sshd or the CLI's readiness wait; failures are logged and ignored), and `claude-sandbox -UpdateClaude` does the same on demand, synchronously. Because a named volume seeds **only** on first creation, sandbox-owned plumbing must NOT live in `/home/claude` (the volume would shadow it and never refresh on rebuild): the runtime scripts, `tmux.conf`, and shell init instead live in `/opt/sandbox/` (the latter as `/opt/sandbox/bashrc.sh`, sourced by a stable one-line hook baked into `~/.bashrc`). Consequently `-Rebuild` refreshes OS packages and `/opt/sandbox` but NOT home-dir content (Claude version, `~/.local` tooling, caches); force a fresh home with `docker compose ... down -v` then start. The `.claude`/`.claude.json`/workspace/env-cache binds nest on top of the volume and keep their prior behavior.

## Environments

Each environment in `environments/` can provide: `compose.yml` (base image, extra volumes), `setup-root.sh`, `setup-user.sh`, `allowed-domains.conf` (additional allowed domains), and config files. Current environments: `base` (Node.js 22), `dotnet` (.NET SDKs 8.0/9.0/10.0/11-preview + NuGet), `php` (PHP 7.4/8.0/8.1/8.2/8.3/8.4/8.5 side by side via the Surý repo, switchable with `use-php`, + Composer, + Xdebug/pcov for coverage and step-debugging (Xdebug off by default, opt in per-command via `XDEBUG_MODE`; pcov drives PHPUnit coverage), + Phpactor language server with PHPStan diagnostics, auto-registered with Claude Code's LSP tool — the tooling is pinned to php8.4 regardless of `use-php`).

## Editing Container Scripts

Shell scripts in `shared/runtime/` and `gateway/` run inside containers. Changes require rebuilding (`docker compose build`) unless using `-SandboxDev` mode which bind-mounts them. The gateway uses `/bin/sh` (Alpine/busybox ash); the claude container and picker use `/bin/bash`. In the claude container the sandbox scripts and config (`tmux-picker.sh`, `new-window.sh`, `tmux.conf`, `bashrc.append` → `bashrc.sh`) are installed under `/opt/sandbox/`, deliberately outside the persistent `/home/claude` volume so rebuilds always refresh them.

**`-SandboxDev` limitations:** Config files like `tmux.conf` are bind-mounted by `dev.compose.yml`, but tmux reads its config only at session creation. Changes to `tmux.conf` always require `-Rebuild` since `-Restart` alone won't cause tmux to re-read the config.

## SSH and Environment Variables

`sshd` does not pass container environment variables to login sessions. To make env vars available in SSH sessions, write them to a file in the container's entrypoint (e.g. `~/.sandbox_env`) and source it in the login shell. Both the claude container (`shared/runtime/entrypoint.sh`) and the picker (`picker/entrypoint.sh`) use this pattern.
