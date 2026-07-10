#!/bin/bash
set -euo pipefail

# Install every supported PHP version side by side from the Ondřej Surý repo
# (packages.sury.org). These are prebuilt .debs, so nothing compiles here.
# 7.4 and 8.0 are EOL upstream but Surý still ships them for bookworm.
# 8.6 has no packages in the Surý bookworm repo yet, so it can't be added here
# (this env installs prebuilt .debs only — no from-source builds).
VERSIONS="7.4 8.0 8.1 8.2 8.3 8.4 8.5"

# Per-version extensions. pcntl is compiled into the CLI SAPI by default, so it
# has no package. mysql provides mysqli + pdo_mysql.
EXTENSIONS="cli apcu bcmath imagick mysql tidy intl mbstring zip"

# --- Surý repo ---
apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https ca-certificates curl gnupg lsb-release unzip

curl -sSL https://packages.sury.org/php/apt.gpg -o /etc/apt/trusted.gpg.d/php.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" \
    > /etc/apt/sources.list.d/php.list

# --- Install all versions + extensions ---
packages=""
for v in $VERSIONS; do
    for e in $EXTENSIONS; do
        packages="$packages php$v-$e"
    done
done

apt-get update && apt-get install -y --no-install-recommends $packages \
&& apt-get clean && rm -rf /var/lib/apt/lists/*

# The highest version wins the `php` alternative by default. Pin it explicitly
# so the default doesn't drift when the version list changes.
update-alternatives --set php /usr/bin/php8.4

# --- use-php: switch the default `php` for the current user, no root needed ---
# Overrides via a symlink in ~/.local/bin (already first on PATH). Composer and
# anything else that calls `php` follow the selection.
cat > /usr/local/bin/use-php << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/.local/bin"
if [ -z "${1:-}" ]; then
    rm -f "$HOME/.local/bin/php"
    hash -r 2>/dev/null || true
    echo "php -> $(command -v php) ($(php -v | head -1))"
    exit 0
fi
bin="/usr/bin/php$1"
if [ ! -x "$bin" ]; then
    echo "PHP $1 is not installed. Available:" >&2
    ls /usr/bin/php[0-9]* 2>/dev/null | sed 's|/usr/bin/|  |' >&2
    exit 1
fi
ln -sf "$bin" "$HOME/.local/bin/php"
hash -r 2>/dev/null || true
echo "php -> $bin ($("$bin" -v | head -1))"
SCRIPT
chmod 755 /usr/local/bin/use-php

# --- Composer (uses whichever PHP is selected via `php` on PATH) ---
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# --- Phpactor (language server) + PHPStan (diagnostics) ---
# Both are PHP programs. Unlike the user's own code, the tooling must NOT follow
# the `use-php` selection: Phpactor needs PHP 8.2+ to even run, so `use-php 7.4`
# would break it. Pin both to a fixed modern interpreter via wrappers. The PHP
# version that PHPStan *analyses for* is a separate concern, set per project in
# phpstan.neon (parameters.phpVersion) — not tied to the interpreter here.
# Keep this in sync with the `update-alternatives --set php` default above.
TOOLING_PHP=/usr/bin/php8.4

curl -fsSL https://github.com/phpactor/phpactor/releases/latest/download/phpactor.phar \
    -o /usr/local/lib/phpactor.phar
curl -fsSL https://github.com/phpstan/phpstan/releases/latest/download/phpstan.phar \
    -o /usr/local/lib/phpstan.phar

for tool in phpactor phpstan; do
    cat > "/usr/local/bin/$tool" << SCRIPT
#!/bin/sh
exec $TOOLING_PHP /usr/local/lib/$tool.phar "\$@"
SCRIPT
    chmod 755 "/usr/local/bin/$tool"
done

# --- Register phpactor with Claude Code's built-in LSP tool ---
# Claude Code's LSP tool stays dormant until a plugin declares a language
# server. Ship a "skills-directory" plugin: auto-discovered, no marketplace /
# install / GitHub required. It can't live in ~/.claude/skills in the image
# because that path is a bind-mounted volume at runtime; stage it here and let
# the shared entrypoint seed it into ~/.claude/skills on container start.
install -D -m 644 /tmp/env/claude-lsp-plugin.json \
    /opt/claude-skills/php-lsp/.claude-plugin/plugin.json
