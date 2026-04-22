#!/bin/sh
# Add picker's public key to shared authorized_keys so it can SSH into sandboxes
# Remove any previous picker keys first, then append the current one
PICKER_KEY=$(cat /home/claude/.ssh/id_ed25519.pub)
sed -i '/claude-sandbox-picker/d' /host-ssh-keys/authorized_keys 2>/dev/null
echo "$PICKER_KEY" >> /host-ssh-keys/authorized_keys

# Persist environment for SSH login sessions (sshd strips the parent env)
{
    echo "HOST_HOSTNAME='${HOST_HOSTNAME}'"
    # Tell picker.sh to reach sandboxes via the Docker host, not localhost.
    # Only set inside this container; on a host shell the default (localhost) applies.
    echo "PICKER_SSH_HOST='host.docker.internal'"
} > /home/claude/.sandbox_env

exec /usr/sbin/sshd -D -e
