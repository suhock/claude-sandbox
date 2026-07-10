#!/bin/bash
set -euo pipefail

# Runs as the `claude` user during the image build. Enables PHPStan diagnostics
# in Phpactor's language server (phpactor + phpstan are installed system-wide by
# setup-root.sh). phpactor.phar already bundles the PHPStan integration, so it
# just needs turning on and pointing at a phpstan binary — no extension install.
#
# This global (user-level) config is loaded for every project without having to
# "trust" the workspace, unlike a project-level .phpactor.json which requires
# `phpactor config:trust`. A project can still override any key with its own
# .phpactor.json — e.g. point .bin at its vendor/bin/phpstan. PHPStan needs a
# phpstan.neon in the project root to have anything to analyse.
#
# We also turn OFF Phpactor's "auto config" (default: on). On language-server
# start, AutoConfigListener asks the Configurator for suggestions (e.g. "enable
# PHPStan for this project?") and, per suggestion, sends the editor an
# interactive YES/NO prompt (window/showMessageRequest), then WRITES the answer
# into a project-level .phpactor.json via apply($change, $answer === 'yes').
# Claude Code's LSP client is headless and never answers "yes", so Phpactor
# records the decline as {"language_server_phpstan.enabled": false} in
# .phpactor.json — which, being project-level, overrides the global enable below
# and silently switches PHPStan diagnostics back off in every workspace. With
# auto_config=false the listener isn't registered at all: no prompt, no spurious
# write, so the enable sticks. (Workspaces already carrying such an auto-written
# .phpactor.json need that stale key removed — this only stops new writes.)
mkdir -p "$HOME/.config/phpactor"
cat > "$HOME/.config/phpactor/phpactor.json" << 'JSON'
{
    "language_server_configuration.auto_config": false,
    "language_server_phpstan.enabled": true,
    "language_server_phpstan.bin": "/usr/local/bin/phpstan"
}
JSON
