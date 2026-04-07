#!/bin/sh
# Add picker's public key to shared authorized_keys so it can SSH into sandboxes
# Remove any previous picker keys first, then append the current one
PICKER_KEY=$(cat /home/claude/.ssh/id_ed25519.pub)
sed -i '/claude-sandbox-picker/d' /host-ssh-keys/authorized_keys 2>/dev/null
echo "$PICKER_KEY" >> /host-ssh-keys/authorized_keys

# Persist environment for SSH login sessions
echo "HOST_HOSTNAME='${HOST_HOSTNAME}'" > /home/claude/.sandbox_env

exec /usr/sbin/sshd -D -e
