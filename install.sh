#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/run.sh"
BIN_DIR="$HOME/.local/bin"
WRAPPER_SCRIPT="$BIN_DIR/claude-sandbox"

# Create bin directory if needed
mkdir -p "$BIN_DIR"

# Write wrapper script
cat > "$WRAPPER_SCRIPT" << EOF
#!/usr/bin/env bash
exec "$SOURCE_SCRIPT" "\$@"
EOF
chmod +x "$WRAPPER_SCRIPT"
echo "Created $WRAPPER_SCRIPT"

# Ensure run.sh is executable
chmod +x "$SOURCE_SCRIPT"

# Write bash completion script
COMPLETER_DIR="$BIN_DIR/.completions"
mkdir -p "$COMPLETER_DIR"
COMPLETER_FILE="$COMPLETER_DIR/claude-sandbox.bash"
ENV_DIR="$SCRIPT_DIR/environments"

cat > "$COMPLETER_FILE" << 'COMP'
_claude_sandbox() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        --environment)
            local envs
            envs="$(ls -d ENVDIR/*/ 2>/dev/null | xargs -n1 basename)"
            COMPREPLY=($(compgen -W "$envs" -- "$cur"))
            ;;
        --workdir)
            COMPREPLY=($(compgen -d -- "$cur"))
            ;;
        *)
            COMPREPLY=($(compgen -W "--start --rebuild --restart --connect --copy-ssh-keys --environment --workdir --ssh-port --sandbox-dev" -- "$cur"))
            ;;
    esac
}
complete -F _claude_sandbox claude-sandbox
COMP
# Patch in the actual environments path (can't expand inside heredoc with 'COMP' quoting)
sed -i "s|ENVDIR|$ENV_DIR|g" "$COMPLETER_FILE"
echo "Created $COMPLETER_FILE"

# Determine shell RC file
SHELL_RC="$HOME/.bashrc"
if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-bash}")" = "zsh" ]; then
    SHELL_RC="$HOME/.zshrc"
fi

# Add bin directory to PATH if not already present
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "" >> "$SHELL_RC"
    echo '# claude-sandbox' >> "$SHELL_RC"
    echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$SHELL_RC"
    echo "[ -f '$COMPLETER_FILE' ] && . '$COMPLETER_FILE'" >> "$SHELL_RC"
    echo "Added $BIN_DIR to PATH and tab completion in $SHELL_RC (restart your terminal for it to take effect)"
else
    # PATH already set — ensure completion is sourced
    if ! grep -q "completions/claude-sandbox" "$SHELL_RC" 2>/dev/null; then
        echo "[ -f '$COMPLETER_FILE' ] && . '$COMPLETER_FILE'" >> "$SHELL_RC"
        echo "Added tab completion to $SHELL_RC"
    fi
fi

echo "Done. Run 'claude-sandbox --help' to get started."
