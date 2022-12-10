#!/bin/sh

## TODO
# FIX mysql_secure_installation
# Investigate crudini

main() {

    if [ ! -t 1 ]; then
        errdie "Autofed has to run interactively"
    fi

    echo "Running Autofed for Ubuntu 22.04"
    autofed_variables || return 1
    apt_update || return 1  # Tested
    adduser_pixelfed || return 1  # Tested
    install_redis || return 1  # Tested
    install_mariadb || return 1  # Tested
    mysql_secure || return 1  #  BROKEN
    prepare_db || return 1  # Tested
    install_packages || return 1  # Tested
    install_PHP_packages || return 1  # Tested
    configure_PHP_inis || return 1  # Tested
    configure_FPM_inis || return 1  # Tested
    install_composer || return 1  # Tested
    git_clone || return 1  # Tested
    artisan_install || return 1  # ??
    artisan_horizon || return 1  # Tested
    set_pathpermissions || return 1  # Tested
    install_nginx || return 1  # ??
    nginx_certbot || return 1  # ?
    systemd_pixelfedhorizon || return 1  # ?
    cron_artisan_schedule || return 1  # Tested
}

### Autofed functions

errdie() {
    >&2 echo -e "\e[1;31m${1}\e[1;m"
    exit 1
}

fancyecho() {
    >&2 echo -e "\e[1;32m${1}\e[1;m"
}

### Autofed Steps
## steps by Shlee
autofed_variables() {
    fancyecho "-----------------------------------------"
    fancyecho "autofed_variables"
    fancyecho "-----------------------------------------"
    fancyecho "Press enter to generate random passwords"
    read -r -p 'PFDomain (pixelfed.au): ' PFDomain
    read -r -p 'PFDomainEmail (pixelfed@pixelfed.au): ' PFDomainEmail
    read -r -p 'DBRootPass (secretDBrootpassword): ' DBRootPass
    read -r -p 'DBPixelfedPass (secretPixlfedDBpassword): ' DBPixelfedPass

    fancyecho "Pixelfed Domain: ${PFDomain}"
    fancyecho "Pixelfed Admin Email: ${PFDomainEmail}"
    fancyecho "MariaDB Root Password: ${DBRootPass}"
    fancyecho "MariaDB Pixelfed Password: ${DBPixelfedPass}"
}

apt_update() {
    fancyecho "-----------------------------------------"
    fancyecho "apt_update"
    fancyecho "-----------------------------------------"
    apt update
}

adduser_pixelfed() {
    fancyecho "-----------------------------------------"
    fancyecho "adduser_pixelfed"
    fancyecho "-----------------------------------------"
    adduser --disabled-password --gecos "" pixelfed
}

install_redis() {
    fancyecho "-----------------------------------------"
    fancyecho "install_redis"
    fancyecho "-----------------------------------------"
    apt -y install redis-server
    systemctl enable --now redis-server
}

install_mariadb() {
    fancyecho "-----------------------------------------"
    fancyecho "install_mariadb"
    fancyecho "-----------------------------------------"
    apt -y install mariadb-server
    systemctl enable --now mariadb
}

# BROKEN
mysql_secure() {
    fancyecho "-----------------------------------------"
    fancyecho "mysql_secure_installation"
    fancyecho "-----------------------------------------"
    /usr/bin/mysql_secure_installation
}

prepare_db() {
    fancyecho "-----------------------------------------"
    fancyecho "prepare_db"
    fancyecho "-----------------------------------------"
    mysql -u root <<EOS
    create database pixelfed;
    grant all privileges on pixelfed.* to 'pixelfed'@'localhost' identified by "${DBPixelfedPass}";
    flush privileges;
EOS
}

install_packages() {
    fancyecho "-----------------------------------------"
    fancyecho "install_packages"
    fancyecho "-----------------------------------------"
    apt -y install ffmpeg unzip zip jpegoptim optipng pngquant gifsicle
}

install_PHP_packages() {
    fancyecho "-----------------------------------------"
    fancyecho "install_PHP_packages"
    fancyecho "-----------------------------------------"
    apt  -y install php8.1-fpm php8.1-cli
    systemctl enable --now php8.1-fpm
    apt  -y install php8.1-bcmath php8.1-curl php8.1-gd php8.1-intl php8.1-mbstring php8.1-xml php8.1-zip php8.1-mysql php-redis php8.1-imagek
}

configure_PHP_inis() {
    fancyecho "-----------------------------------------"
    fancyecho "configure_PHP_inis"
    fancyecho "-----------------------------------------"
    sed -i 's/^post_max_size = .*/post_max_size = 300M/' /etc/php/8.1/cli/php.ini
    sed -i 's/^file_uploads = .*/file_uploads = On/' /etc/php/8.1/cli/php.ini
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 300M/' /etc/php/8.1/cli/php.ini
    sed -i 's/^max_file_uploads = .*/max_file_uploads = 20/' /etc/php/8.1/cli/php.ini
    sed -i 's/^max_execution_time = .*/max_execution_time = 120/' /etc/php/8.1/cli/php.ini

    sed -i 's/^post_max_size = .*/post_max_size = 300M/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^file_uploads = .*/file_uploads = On/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 300M/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^max_file_uploads = .*/max_file_uploads = 20/' /etc/php/8.1/fpm/php.ini
    sed -i 's/^max_execution_time = .*/max_execution_time = 120/' /etc/php/8.1/fpm/php.ini
}

configure_FPM_inis() {
    fancyecho "-----------------------------------------"
    fancyecho "configure_FPM_inis"
    fancyecho "-----------------------------------------"
    cp /etc/php/8.1/fpm/pool.d/www.conf /etc/php/8.1/fpm/pool.d/pixelfed.conf
    sed -i 's/\[www\]/[pixelfed]/' /etc/php/8.1/fpm/pool.d/pixelfed.conf
    sed -i 's/^user = .*/user = pixelfed/' /etc/php/8.1/fpm/pool.d/pixelfed.conf
    sed -i 's/^group = .*/group = www-data/' /etc/php/8.1/fpm/pool.d/pixelfed.conf
    sed -i 's/^listen = .*/listen = \/run\/php\/php8.1-fpm-pixelfed.sock/' /etc/php/8.1/fpm/pool.d/pixelfed.conf
    systemctl restart php8.1-fpm
}

install_composer() {
    fancyecho "-----------------------------------------"
    fancyecho "install_composer"
    fancyecho "-----------------------------------------"
    curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
}

git_clone() {
    fancyecho "-----------------------------------------"
    fancyecho "git_clone"
    fancyecho "-----------------------------------------"
    runuser - pixelfed -c "git clone -b dev https://github.com/pixelfed/pixelfed.git pixelfed"
    runuser - pixelfed -c "cd pixelfed && composer install --no-ansi --no-interaction --optimize-autoloader"
}

artisan_install() {
    fancyecho "-----------------------------------------"
    fancyecho "artisan_install"
    fancyecho "-----------------------------------------"
    runuser - pixelfed -c "cd pixelfed && php artisan install"
}

artisan_horizon() {
    fancyecho "-----------------------------------------"
    fancyecho "artisan_horizon"
    fancyecho "-----------------------------------------"
    runuser - pixelfed -c "cd pixelfed && php artisan horizon:install"
    runuser - pixelfed -c "cd pixelfed && php artisan horizon:publish"
}

set_pathpermissions() {
    fancyecho "-----------------------------------------"
    fancyecho "set_pathpermissions"
    chown -R pixelfed:www-data /home/pixelfed
}

install_nginx() {
    fancyecho "-----------------------------------------"
    fancyecho "install_nginx"
    fancyecho "-----------------------------------------"
    apt -y install nginx certbot python3-certbot-nginx
    systemctl enable --now nginx
}

# BROKEN
nginx_certbot() {
    fancyecho "-----------------------------------------"
    fancyecho "nginx_certbot"
    fancyecho "-----------------------------------------"
    rm /etc/nginx/sites-enabled/default
    certbot certonly --standalone --noninteractive --agree-tos -m ${PFDomainEmail} -d ${PFDomain}
    cp /home/pixelfed/pixelfed/contrib/nginx.conf /etc/nginx/sites-available/pixelfed.conf

    sed -i "s/server_name .*/server_name ${PFDomain};/" /etc/nginx/sites-available/pixelfed.conf  # Changes both references
    sed -i 's/root .*/root \/home\/pixelfed\/pixelfed\/public\/\;/' /etc/nginx/sites-available/pixelfed.conf
    sed -i "s/ssl_certificate .*/ssl_certificate \/etc\/letsencrypt\/live\/${PFDomain}\/fullchain.pem\;/" /etc/nginx/sites-available/pixelfed.conf
    sed -i "s/ssl_certificate_key .*/ssl_certificate_key \/etc\/letsencrypt\/live\/${PFDomain}\/privkey.pem;/" /etc/nginx/sites-available/pixelfed.conf
    sed -i 's/fastcgi_pass .*/fastcgi_pass unix:\/run\/php\/php8.1-fpm-pixelfed.sock;/' /etc/nginx/sites-available/pixelfed.conf

    ln -s /etc/nginx/sites-available/pixelfed.conf /etc/nginx/sites-enabled/
    systemctl reload nginx && fancyecho "nginx reloaded"
}

systemd_pixelfedhorizon() {
    fancyecho "-----------------------------------------"
    fancyecho "systemd_pixelfedhorizon"
    fancyecho "-----------------------------------------"
    
tee /etc/systemd/system/pixelfedhorizon.service <<EOF
[Unit]
Description=Pixelfed task queueing via Laravel Horizon
After=network.target
Requires=mariadb
Requires=php8.1-fpm
Requires=redis
Requires=nginx

[Service]
Type=simple
ExecStart=/usr/bin/php artisan horizon --environment=production
ExecStop=/usr/bin/php artisan horizon:terminate --wait
User=pixelfed
Group=www-data
WorkingDirectory=/home/pixelfed/pixelfed/
Restart=on-failure

KillSignal=SIGCONT
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target

EOF

    systemctl daemon-reload
    systemctl enable --now pixelfedhorizon
}

cron_artisan_schedule() {
    fancyecho "-----------------------------------------"
    fancyecho "cron_artisan_schedule"
    fancyecho "-----------------------------------------"
    croncmd="/usr/bin/php /home/pixelfed/pixelfed/artisan schedule:run >> /dev/null 2>&1"
    cronjob="* * * * * $croncmd"
    ( crontab -l | grep -v -F "$croncmd" ; echo "$cronjob" ) | crontab -
}

## main always at the bottom
main "$@" || exit 1
