FROM node:22-slim

RUN apt-get update && apt-get install -y \
    git curl bash build-essential python3 wget libicu-dev \
    && npm install -g @anthropic-ai/claude-code \
    && wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet \
    && ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && rm /tmp/dotnet-install.sh \
    && apt-get clean

# Rename the existing node user/group to claude
RUN usermod -l claude node && \
    groupmod -n claude node && \
    usermod -d /home/claude -m claude

# Give claude user ownership of npm global dir so Claude Code can self-update
RUN chown -R claude:claude /usr/local/lib/node_modules /usr/local/bin

# Shadow git with a wrapper blocking destructive operations
RUN printf '#!/bin/sh\n\
case "$*" in\n\
  *"reset --hard"*|\
*"filter-branch"*|\
*"rebase"*|\
*"clean -f"*|\
*"clean -fd"*|\
*"reflog expire"*|\
*"gc --prune"*|\
*"push"*|\
*"fetch"*|\
*"pull"*)\n\
    echo "Blocked git operation in sandbox: git $*" >&2\n\
    exit 1 ;;\n\
  *) exec /usr/bin/git "$@" ;;\n\
esac\n' > /usr/local/bin/git \
    && chmod +x /usr/local/bin/git

USER claude

# Disable auto-updates — version is baked into the image, and the sandbox
# network doesn't allow reaching the npm registry for version checks.
RUN mkdir -p /home/claude/.claude && \
    printf '{"autoUpdaterStatus":"disabled"}\n' > /home/claude/.claude/settings.json

WORKDIR /workspace

CMD ["bash"]
