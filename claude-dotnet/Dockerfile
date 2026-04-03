FROM mcr.microsoft.com/dotnet/sdk:10.0

RUN apt-get update && apt-get install -y \
    git curl bash build-essential python3 \
    openssh-server tmux \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean

# Configure sshd
RUN mkdir -p /run/sshd && \
    sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "AuthorizedKeysFile .ssh/authorized_keys" >> /etc/ssh/sshd_config && \
    apt-get install -y sudo && \
    echo "claude ALL=(root) NOPASSWD: /usr/sbin/sshd" >> /etc/sudoers.d/claude-sshd && \
    chmod 440 /etc/sudoers.d/claude-sshd

# Rename the existing ubuntu user/group (UID/GID 1000) to claude,
# matching the UID used by claude-base (host volumes are owned by UID 1000)
RUN usermod -l claude ubuntu && \
    groupmod -n claude ubuntu && \
    usermod -d /home/claude -m claude && \
    passwd -d claude

USER claude

RUN mkdir -p ~/.ssh && chmod 700 ~/.ssh

# Configure tmux
RUN echo 'set -g mouse on' >> ~/.tmux.conf && \
    echo 'set -g history-limit 100000' >> ~/.tmux.conf && \
    echo "set -g terminal-overrides 'xterm*:smcup@:rmcup@'" >> ~/.tmux.conf

# Ensure SSH sessions get the right PATH and env, auto-attach to claude tmux
RUN echo 'export PATH="/home/claude/.local/bin:/home/claude/.dotnet/tools:${PATH}"' >> ~/.bashrc && \
    echo 'export TERM=xterm-256color' >> ~/.bashrc && \
    echo 'cd /workspace' >> ~/.bashrc && \
    echo 'if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then exec tmux attach -t claude; fi' >> ~/.bashrc

RUN dotnet tool install --global csharp-ls

# Install Claude Code natively (installs to ~/.local/bin/claude)
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/claude/.local/bin:/home/claude/.dotnet/tools:${PATH}"

RUN claude install

COPY --chmod=755 --chown=claude:claude entrypoint.sh /entrypoint.sh

WORKDIR /workspace

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
