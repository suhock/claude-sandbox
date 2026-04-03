#!/bin/bash
set -euo pipefail

apt-get update && apt-get install -y \
    unzip libzip-dev libicu-dev libonig-dev \
&& docker-php-ext-install zip intl mbstring \
&& apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Composer globally
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
