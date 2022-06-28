#!/bin/sh

DBRootPass="secretrootpasswordhere"
DBPixelfedPass="secretpasswordhere"

main() {

    if [ ! -t 1 ]; then
        errdie "Autofed has to run interactively"
    fi

    echo "Running Autofed for Ubuntu 22.04"
    apt_update || return 1
    install_redis || return 1
    install_mariadb || return 1
    mysql_secure_installation || return 1
    prepare_db || return 1
    install_packages || return 1
    install_PHP_packages || return 1
    configure_PHP_inis || return 1
    configure_FPM_inis || return 1
    install_composer || return 1
    adduser_pixelfed || return 1
    gitclone || return 1
}

### Autofed functions

errdie() {
    >&2 echo "\e[1;31m${1}\e[1;m"
    exit 1
}

fancyecho() {
    >&2 echo "\e[1;32m${1}\e[1;m"
}

### Autofed Steps
## steps by Shlee

apt_update() {
    fancyecho "-----------------------------------------"
    fancyecho "apt_update"
    apt update
}

install_redis() {
    fancyecho "-----------------------------------------"
    fancyecho "install_redis"
    apt -y install redis-server
    systemctl enable --now redis-server
}

install_mariadb() {
    fancyecho "-----------------------------------------"
    fancyecho "install_mariadb"
    apt -y install mariadb-server
    systemctl enable --now mariadb
}

mysql_secure_installation() {
    fancyecho "-----------------------------------------"
    fancyecho "mysql_secure_installation"

mysql_secure_installation 2>/dev/null <<MSI

n
y
${DBRootPass}
${DBRootPass}
y
y
y
y

MSI
}

prepare_db() {
    fancyecho "-----------------------------------------"
    fancyecho "prepare_db"
    mysql -u root <<EOS
    create database pixelfed;
    grant all privileges on pixelfed.* to 'pixelfed'@'localhost' identified by "${DBPixelfedPass}";
    flush privileges;
EOS
}

install_packages() {
    fancyecho "-----------------------------------------"
    fancyecho "install_packages"
    apt -y install ffmpeg unzip zip jpegoptim optipng pngquant gifsicle
}

install_PHP_packages() {
    fancyecho "-----------------------------------------"
    fancyecho "install_PHP_packages"
    apt -y install php8.1-fpm php8.1-cli
    apt -y install php8.1-bcmath php8.1-curl php8.1-gd php8.1-intl php8.1-mbstring php8.1-xml php8.1-zip php8.1-mysql php-redis
}

configure_PHP_inis() {
    fancyecho "-----------------------------------------"
    fancyecho "configure_PHP_inis"
    sed -i "s/post_max_size = .*/post_max_size = 300M/g" /etc/php/8.1/cli/php.ini
    sed -i "s/file_uploads = .*/file_uploads = On/g" /etc/php/8.1/cli/php.ini
    sed -i "s/upload_max_filesize = .*/upload_max_filesize = 300M/g" /etc/php/8.1/cli/php.ini
    sed -i "s/max_file_uploads = .*/max_file_uploads = 20/g" /etc/php/8.1/cli/php.ini
    sed -i "s/max_execution_time = .*/max_execution_time = 120/g" /etc/php/8.1/cli/php.ini

    sed -i "s/post_max_size = .*/post_max_size = 300M/g" /etc/php/8.1/fpm/php.ini
    sed -i "s/file_uploads = .*/file_uploads = On/g" /etc/php/8.1/fpm/php.ini
    sed -i "s/upload_max_filesize = .*/upload_max_filesize = 300M/g" /etc/php/8.1/fpm/php.ini
    sed -i "s/max_file_uploads = .*/max_file_uploads = 20/g" /etc/php/8.1/fpm/php.ini
    sed -i "s/max_execution_time = .*/max_execution_time = 120/g" /etc/php/8.1/fpm/php.ini
}

configure_FPM_inis() {
    fancyecho "-----------------------------------------"
    fancyecho "configure_FPM_inis"
    cp /etc/php/8.1/fpm/pool.d/www.conf /etc/php/8.1/fpm/pool.d/pixelfed.conf
    sed 's/\[www\]/[pixelfed]/g'
#     sed 's/user = .*/user = pixelfed/g' /etc/php/8.1/fpm/pool.d/pixelfed.conf
#     sed 's/group = .*/group = pixelfed/g' /etc/php/8.1/fpm/pool.d/pixelfed.conf
#     sed 's/listen = .*/listen = \/run\/php\/php8.1-fpm-pixelfed.sock/g' /etc/php/8.1/fpm/pool.d/pixelfed.conf
#     systemctl restart php8.1-fpm
}

install_composer() {
    fancyecho "-----------------------------------------"
    fancyecho "install_composer"
    curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
}

adduser_pixelfed() {
    fancyecho "-----------------------------------------"
    fancyecho "adduser_pixelfed"
    adduser --disabled-password --gecos "" pixelfed
}

gitclone() {
    fancyecho "-----------------------------------------"
    fancyecho "gitclone"
    runuser - pixelfed -c "git clone -b dev https://github.com/pixelfed/pixelfed.git pixelfed"
    runuser - pixelfed -c "cd pixelfed && composer install --no-ansi --no-interaction --optimize-autoloader"
}

# example_thing() {
#     fancyecho "-----------------------------------------"
#     fancyecho "example_thing"
# }

# example_thing() {
#     fancyecho "-----------------------------------------"
#     fancyecho "example_thing"
# }

## main always at the bottom
main "$@" || exit 1
