#!/bin/sh

RootPass=""
PixelfedDBpass=""

main() {

    if [ ! -t 1 ]; then
        err "Autofed has to run interactively"
    fi

    echo "Running Autofed for Ubuntu 22.04"
    install_redis || return 1
    install_mariadb || return 1
    #mysql_secure_installation || return 1
}

err() {
    >&2 echo "$1"
    exit 1
}

main "$@" || exit 1


install_redis() {
    apt -y install redis-server
    systemctl enable --now redis-server
}

install_mariadb() {
    apt -y install mariadb-server
    systemctl enable --now mariadb
}

mysql_secure_installation() {
    ## mysql_secure_installation
}




