#!/bin/bash
set -euo pipefail

echo 'export PATH="/home/claude/.dotnet/tools:${PATH}"' >> ~/.bashrc
export PATH="/home/claude/.dotnet/tools:${PATH}"
dotnet tool install --global csharp-ls

# Configure NuGet (host cache as read-only fallback, etc.)
mkdir -p ~/.nuget/NuGet
cp /tmp/env/config/NuGet.Config ~/.nuget/NuGet/NuGet.Config
