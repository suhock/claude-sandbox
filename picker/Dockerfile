FROM alpine:3.21

RUN apk add --no-cache openssh-server openssh-client bash docker-cli ncurses sudo

# sshd setup (key-only auth, same pattern as sandbox)
RUN mkdir -p /run/sshd \
    && ssh-keygen -A \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/' /etc/ssh/sshd_config \
    && echo "AuthorizedKeysFile none" >> /etc/ssh/sshd_config \
    && echo "AuthorizedKeysCommand /etc/ssh/authorized_keys_command.sh %u" >> /etc/ssh/sshd_config \
    && echo "AuthorizedKeysCommandUser root" >> /etc/ssh/sshd_config \
    && echo "AllowAgentForwarding yes" >> /etc/ssh/sshd_config

# AuthorizedKeysCommand (reads from host mount)
RUN printf '#!/bin/sh\ncat /host-ssh-keys/authorized_keys 2>/dev/null\n' > /etc/ssh/authorized_keys_command.sh \
    && chmod 755 /etc/ssh/authorized_keys_command.sh

# Create claude user with picker as login shell (wrapper runs docker as root via sudo)
COPY --chmod=755 picker.sh /usr/local/bin/picker.sh
RUN adduser -D -u 1000 -s /usr/local/bin/picker.sh claude \
    && passwd -u claude \
    && mkdir -p /home/claude/.ssh \
    && chmod 700 /home/claude/.ssh \
    && chown claude:claude /home/claude/.ssh \
    && ssh-keygen -t ed25519 -f /home/claude/.ssh/id_ed25519 -N "" -q -C "claude-sandbox-picker" \
    && chown claude:claude /home/claude/.ssh/id_ed25519 /home/claude/.ssh/id_ed25519.pub \
    && echo "claude ALL=(root) NOPASSWD: /usr/bin/docker" > /etc/sudoers.d/claude-docker \
    && chmod 440 /etc/sudoers.d/claude-docker

RUN : > /etc/motd

EXPOSE 22
COPY --chmod=755 entrypoint.sh /entrypoint.sh
CMD ["/entrypoint.sh"]
