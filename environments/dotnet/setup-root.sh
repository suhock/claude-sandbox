#!/bin/bash
set -euo pipefail

# The base image (mcr.microsoft.com/dotnet/sdk:10.0) installs .NET to /usr/share/dotnet.
# Install additional SDKs side-by-side into the same DOTNET_ROOT so that a single
# `dotnet` reports all of them via `dotnet --list-sdks` and can target each framework.
DOTNET_ROOT="${DOTNET_ROOT:-/usr/share/dotnet}"

curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh

# .NET 8.0 (LTS) and 9.0 (STS)
/tmp/dotnet-install.sh --channel 8.0 --install-dir "$DOTNET_ROOT"
/tmp/dotnet-install.sh --channel 9.0 --install-dir "$DOTNET_ROOT"

# .NET 11 preview
/tmp/dotnet-install.sh --channel 11.0 --quality preview --install-dir "$DOTNET_ROOT"

rm -f /tmp/dotnet-install.sh
