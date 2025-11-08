#!/bin/bash
set -euo pipefail

## Autofed - Automated Pixelfed Setup for Ubuntu 24.04
## Version: 2.0

LOGFILE="/var/log/autofed-$(date +%Y%m%d-%H%M%S).log"
PHP_VERSION="8.4"

main() {
    check_prerequisites || return 1
    
    exec > >(tee -a "$LOGFILE")
    exec 2>&1
    fancyecho "Starting Autofed for Ubuntu 24.04"
    fancyecho "Log file: $LOGFILE"
    
    autofed_variables || return 1
    show_summary || return 1
    apt_update || return 1
    adduser_pixelfed || return 1
    install_redis || return 1
    install_mariadb || return 1
    prepare_db || return 1
    install_packages || return 1
    install_PHP_packages || return 1
    configure_PHP_inis || return 1
    configure_FPM_inis || return 1
    install_composer || return 1
    git_clone || return 1
    artisan_install || return 1
    artisan_horizon || return 1
    set_pathpermissions || return 1
    systemd_pixelfedhorizon || return 1
    cron_artisan_schedule || return 1
    
    fancyecho "========================================="
    fancyecho "Installation complete!"
    fancyecho "Log file: $LOGFILE"
    fancyecho "========================================="
}

### Helper functions

errdie() {
    >&2 echo -e "\e[1;31m[ERROR] ${1}\e[0m"
    exit 1
}

fancyecho() {
    echo -e "\e[1;32m${1}\e[0m"
}

validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

### Setup Steps

check_prerequisites() {
    fancyecho "-----------------------------------------"
    fancyecho "Checking prerequisites"
    fancyecho "-----------------------------------------"
    
    if [ "$EUID" -ne 0 ]; then
        errdie "This script must be run as root"
    fi
    
    if [ ! -f /etc/os-release ]; then
        errdie "Cannot detect OS version"
    fi
    
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]] || [[ ! "$VERSION_ID" =~ ^(22.04|24.04)$ ]]; then
        errdie "This script requires Ubuntu 22.04 or 24.04"
    fi
    
    fancyecho "✓ Running as root"
    fancyecho "✓ Ubuntu $VERSION_ID detected"
}

autofed_variables() {
    fancyecho "-----------------------------------------"
    fancyecho "Configuration"
    fancyecho "-----------------------------------------"
    
    while true; do
        read -r -p 'Pixelfed Domain (e.g., pixelfed.example.com): ' PFDomain
        if validate_domain "$PFDomain"; then
            break
        else
            echo "Invalid domain format. Please try again."
        fi
    done
    
    while true; do
        read -r -p 'Admin Email (e.g., admin@example.com): ' PFDomainEmail
        if validate_email "$PFDomainEmail"; then
            break
        else
            echo "Invalid email format. Please try again."
        fi
    done
    
    echo ""
    fancyecho "Password Generation"
    read -r -p 'Generate random passwords? (Y/n): ' gen_pass
    gen_pass=${gen_pass:-Y}
    
    if [[ "$gen_pass" =~ ^[Yy]$ ]]; then
        DBRootPass=$(generate_password)
        DBPixelfedPass=$(generate_password)
        fancyecho "✓ Passwords generated"
    else
        while true; do
            read -r -s -p 'MariaDB Root Password: ' DBRootPass
            echo ""
            read -r -s -p 'Confirm MariaDB Root Password: ' DBRootPass2
            echo ""
            if [ "$DBRootPass" = "$DBRootPass2" ] && [ -n "$DBRootPass" ]; then
                break
            else
                echo "Passwords don't match or are empty. Try again."
            fi
        done
        
        while true; do
            read -r -s -p 'MariaDB Pixelfed User Password: ' DBPixelfedPass
            echo ""
            read -r -s -p 'Confirm MariaDB Pixelfed User Password: ' DBPixelfedPass2
            echo ""
            if [ "$DBPixelfedPass" = "$DBPixelfedPass2" ] && [ -n "$DBPixelfedPass" ]; then
                break
            else
                echo "Passwords don't match or are empty. Try again."
            fi
        done
    fi
    
    # Save credentials securely
    CRED_FILE="/root/.autofed_credentials"
    cat > "$CRED_FILE" <<EOF
# Autofed Installation Credentials
# Generated: $(date)
# Domain: $PFDomain

PIXELFED_DOMAIN=$PFDomain
PIXELFED_EMAIL=$PFDomainEmail
DB_ROOT_PASSWORD=$DBRootPass
DB_PIXELFED_PASSWORD=$DBPixelfedPass
EOF
    chmod 600 "$CRED_FILE"
    fancyecho "✓ Credentials saved to $CRED_FILE"
}

show_summary() {
    fancyecho "-----------------------------------------"
    fancyecho "Installation Summary"
    fancyecho "-----------------------------------------"
    echo "Domain: $PFDomain"
    echo "Email: $PFDomainEmail"
    echo "PHP Version: $PHP_VERSION"
    echo "Database: MariaDB"
    echo "Cache: Redis"
    echo ""
    read -r -p 'Proceed with installation? (y/N): ' confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        errdie "Installation cancelled by user"
    fi
}

apt_update() {
    fancyecho "-----------------------------------------"
    fancyecho "Updating package lists"
    fancyecho "-----------------------------------------"
    apt-get update -y
    apt-get upgrade -y
}

adduser_pixelfed() {
    fancyecho "-----------------------------------------"
    fancyecho "Creating pixelfed user"
    fancyecho "-----------------------------------------"
    if id "pixelfed" &>/dev/null; then
        fancyecho "✓ User pixelfed already exists"
    else
        adduser --disabled-password --gecos "" pixelfed
        fancyecho "✓ User pixelfed created"
    fi
}

install_redis() {
    fancyecho "-----------------------------------------"
    fancyecho "Installing Redis"
    fancyecho "-----------------------------------------"
    apt-get install -y redis-server
    systemctl enable redis-server
    systemctl start redis-server
    fancyecho "✓ Redis installed and started"
}

install_mariadb() {
    fancyecho "-----------------------------------------"
    fancyecho "Installing MariaDB"
    fancyecho "-----------------------------------------"
    apt-get install -y mariadb-server mariadb-client
    systemctl enable mariadb
    systemctl start mariadb
    
    # Secure installation
    mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DBRootPass}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    
    fancyecho "✓ MariaDB installed and secured"
}

prepare_db() {
    fancyecho "-----------------------------------------"
    fancyecho "Creating Pixelfed database"
    fancyecho "-----------------------------------------"
    
    mysql -u root -p"${DBRootPass}" <<EOF
CREATE DATABASE IF NOT EXISTS pixelfed CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'pixelfed'@'localhost' IDENTIFIED BY '${DBPixelfedPass}';
GRANT ALL PRIVILEGES ON pixelfed.* TO 'pixelfed'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    fancyecho "✓ Database and user created"
}

install_packages() {
    fancyecho "-----------------------------------------"
    fancyecho "Installing system packages"
    fancyecho "-----------------------------------------"
    apt-get install -y \
        ffmpeg \
        unzip \
        zip \
        jpegoptim \
        optipng \
        pngquant \
        gifsicle \
        libvips42 \
        git \
        curl \
        software-properties-common
    
    fancyecho "✓ System packages installed"
}

install_PHP_packages() {
    fancyecho "-----------------------------------------"
    fancyecho "Installing PHP $PHP_VERSION"
    fancyecho "-----------------------------------------"
    
    add-apt-repository -y ppa:ondrej/php
    apt-get update -y
    
    apt-get install -y \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-redis \
        php${PHP_VERSION}-vips
    
    systemctl enable php${PHP_VERSION}-fpm
    systemctl start php${PHP_VERSION}-fpm
    
    fancyecho "✓ PHP packages installed"
}

configure_PHP_inis() {
    fancyecho "-----------------------------------------"
    fancyecho "Configuring PHP settings"
    fancyecho "-----------------------------------------"
    
    for ini in /etc/php/${PHP_VERSION}/cli/php.ini /etc/php/${PHP_VERSION}/fpm/php.ini; do
        sed -i 's/^post_max_size = .*/post_max_size = 300M/' "$ini"
        sed -i 's/^file_uploads = .*/file_uploads = On/' "$ini"
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 300M/' "$ini"
        sed -i 's/^max_file_uploads = .*/max_file_uploads = 20/' "$ini"
        sed -i 's/^max_execution_time = .*/max_execution_time = 120/' "$ini"
    done
    
    fancyecho "✓ PHP configuration updated"
}

configure_FPM_inis() {
    fancyecho "-----------------------------------------"
    fancyecho "Configuring PHP-FPM pool"
    fancyecho "-----------------------------------------"
    
    cp /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf /etc/php/${PHP_VERSION}/fpm/pool.d/pixelfed.conf
    
    sed -i 's/\[www\]/[pixelfed]/' /etc/php/${PHP_VERSION}/fpm/pool.d/pixelfed.conf
    sed -i 's/^user = .*/user = pixelfed/' /etc/php/${PHP_VERSION}/fpm/pool.d/pixelfed.conf
    sed -i 's/^group = .*/group = www-data/' /etc/php/${PHP_VERSION}/fpm/pool.d/pixelfed.conf
    sed -i "s|^listen = .*|listen = /run/php/php${PHP_VERSION}-fpm-pixelfed.sock|" /etc/php/${PHP_VERSION}/fpm/pool.d/pixelfed.conf
    
    systemctl restart php${PHP_VERSION}-fpm
    
    fancyecho "✓ PHP-FPM pool configured"
}

install_composer() {
    fancyecho "-----------------------------------------"
    fancyecho "Installing Composer"
    fancyecho "-----------------------------------------"
    
    if command -v composer &> /dev/null; then
        fancyecho "✓ Composer already installed"
        return 0
    fi
    
    EXPECTED_CHECKSUM="$(curl -sS https://composer.github.io/installer.sig)"
    curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"
    
    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
        rm /tmp/composer-setup.php
        errdie "Composer installer checksum mismatch"
    fi
    
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm /tmp/composer-setup.php
    
    fancyecho "✓ Composer installed"
}

git_clone() {
    fancyecho "-----------------------------------------"
    fancyecho "Cloning Pixelfed repository"
    fancyecho "-----------------------------------------"
    
    if [ -d /home/pixelfed/pixelfed ]; then
        fancyecho "⚠ Pixelfed directory already exists, skipping clone"
        return 0
    fi
    
    # Clone the dev branch
    runuser -u pixelfed -- git clone -b dev https://github.com/shleeable/pixelfed-staging.git /home/pixelfed/pixelfed
    
    # Install dependencies
    runuser -u pixelfed -- bash -c "cd /home/pixelfed/pixelfed && composer install --no-ansi --no-interaction --optimize-autoloader"
    
    fancyecho "✓ Pixelfed cloned and dependencies installed"
}

artisan_install() {
    fancyecho "-----------------------------------------"
    fancyecho "Running Pixelfed installer"
    fancyecho "-----------------------------------------"
    
    if [ ! -d /home/pixelfed/pixelfed ]; then
        errdie "Pixelfed directory not found. Git clone may have failed."
    fi
    
    fancyecho "Running Pixelfed installer with pre-filled credentials..."
    
    runuser -u pixelfed -- bash -c "cd /home/pixelfed/pixelfed && php artisan install \
        --domain='${PFDomain}' \
        --name='Pixelfed' \
        --db-driver='mysql' \
        --db-host='127.0.0.1' \
        --db-port='3306' \
        --db-database='pixelfed' \
        --db-username='pixelfed' \
        --db-password='${DBPixelfedPass}' \
        --redis-host='localhost' \
        --redis-port='6379' \
        --redis-password=''"
    
    fancyecho "✓ Pixelfed installer completed"
}

artisan_horizon() {
    fancyecho "-----------------------------------------"
    fancyecho "Setting up Laravel Horizon"
    fancyecho "-----------------------------------------"
    
    runuser -u pixelfed -- bash -c "cd /home/pixelfed/pixelfed && php artisan horizon:install"
    
    fancyecho "✓ Horizon configured"
}

set_pathpermissions() {
    fancyecho "-----------------------------------------"
    fancyecho "Setting file permissions"
    fancyecho "-----------------------------------------"
    
    chown -R pixelfed:www-data /home/pixelfed/pixelfed
    chmod -R 755 /home/pixelfed/pixelfed
    chmod -R 775 /home/pixelfed/pixelfed/storage /home/pixelfed/pixelfed/bootstrap/cache
    
    fancyecho "✓ Permissions set"
}

systemd_pixelfedhorizon() {
    fancyecho "-----------------------------------------"
    fancyecho "Creating systemd service"
    fancyecho "-----------------------------------------"
    
    cat > /etc/systemd/system/pixelfedhorizon.service <<EOF
[Unit]
Description=Pixelfed task queueing via Laravel Horizon
After=network.target mariadb.service redis-server.service
Wants=mariadb.service redis-server.service

[Service]
Type=simple
ExecStart=/usr/bin/php artisan horizon
User=pixelfed
Group=www-data
WorkingDirectory=/home/pixelfed/pixelfed
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable pixelfedhorizon
    
    fancyecho "✓ Systemd service created (not started yet)"
    fancyecho "  Start with: systemctl start pixelfedhorizon"
}

cron_artisan_schedule() {
    fancyecho "-----------------------------------------"
    fancyecho "Setting up cron job"
    fancyecho "-----------------------------------------"
    
    croncmd="/usr/bin/php /home/pixelfed/pixelfed/artisan schedule:run >> /dev/null 2>&1"
    cronjob="* * * * * $croncmd"
    
    # Add to pixelfed user's crontab
    runuser -u pixelfed -- bash -c "(crontab -l 2>/dev/null | grep -v -F '$croncmd' ; echo '$cronjob') | crontab -"
    
    fancyecho "✓ Cron job added for pixelfed user"
}

## Main execution
main "$@" || exit 1
