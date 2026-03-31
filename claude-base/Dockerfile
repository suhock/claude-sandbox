FROM node:22-slim

RUN apt-get update && apt-get install -y \
    git curl bash build-essential python3 \
    && apt-get clean

# Rename the existing node user/group to claude
RUN usermod -l claude node && \
    groupmod -n claude node && \
    usermod -d /home/claude -m claude

USER claude

# Install Claude Code natively (installs to ~/.local/bin/claude)
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/claude/.local/bin:${PATH}"

WORKDIR /workspace

CMD ["bash"]
