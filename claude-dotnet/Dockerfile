FROM mcr.microsoft.com/dotnet/sdk:10.0

RUN apt-get update && apt-get install -y \
    git curl bash build-essential python3 \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean

# Rename the existing ubuntu user/group (UID/GID 1000) to claude,
# matching the UID used by claude-base (host volumes are owned by UID 1000)
RUN usermod -l claude ubuntu && \
    groupmod -n claude ubuntu && \
    usermod -d /home/claude -m claude

USER claude

RUN dotnet tool install --global csharp-ls

# Install Claude Code natively (installs to ~/.local/bin/claude)
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/claude/.local/bin:/home/claude/.dotnet/tools:${PATH}"

RUN claude install

COPY --chmod=755 --chown=claude:claude entrypoint.sh /entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
