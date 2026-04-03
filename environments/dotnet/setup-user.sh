#!/bin/bash
set -euo pipefail

echo 'export PATH="/home/claude/.dotnet/tools:${PATH}"' >> ~/.bashrc
export PATH="/home/claude/.dotnet/tools:${PATH}"
dotnet tool install --global csharp-ls
