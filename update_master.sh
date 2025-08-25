#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="7"

clr_rst='\033[0m'
clr_red='\033[1;31m'
clr_grn='\033[1;32m'
clr_ylw='\033[1;33m'

log() {
    printf "$1$2$clr_rst\n"
}

set +u
if [[ -z "$1" ]]; then
    log "$clr_red" "Необходимо передать новый релиз первым параметром"
    log "$clr_ylw" "Пример: ./update_master.sh 82"
    exit
fi
set -u

SCRIPT_NAME="update_$1.sh"

get_docker_credentials() {
    if [[ -f 'credentials.txt' ]]; then
        source credentials.txt
        return
    fi

    if [[ -f 'docker-registry.credentials' ]]; then
        DOCKER_LOGIN="$(grep login docker-registry.credentials | sed 's/login://g' | sed 's/ //g')"
        DOCKER_PASS="$(grep pass docker-registry.credentials | sed 's/pass://g' | sed 's/ //g')"
        return
    fi

    log "$clr_red" "Не найдены логин и пароль к HRlink Docker Registry. Обратитесь в поддержку."
    exit 1
}

check_for_updates() {
    script=$1
    current_version=$2

    if ! [[ -f ./scripts/update/$script ]]; then
        dl_script "$script"
        return
    fi

    if [[ -z $current_version ]]; then
        current_version=$(grep SCRIPT_VERSION ./scripts/update/$script | cut -d '=' -f 2 | tr -d ' "\n')
    fi

    docker_auth=$(echo -n "$DOCKER_LOGIN:$DOCKER_PASS" | base64 -w0)
    new_version=$(curl -s -H "Authorization: Basic $docker_auth" \
     https://docker.hr-link.ru/repository/on-prem-files/update/$script | grep "SCRIPT_VERSION" | sed 's/"//g' | cut -d '=' -f 2 | head -n1)

    if [[ $new_version -gt $current_version ]]; then
        log "$clr_ylw" "Доступна новая версия скрипта $script - $new_version. Текущая - $current_version"
        dl_script "$script"
    fi
}

dl_script() {
    SCRIPT_NAME=$1

    mkdir -p ./scripts/update/
    wget --user $DOCKER_LOGIN --password $DOCKER_PASS https://docker.hr-link.ru/repository/on-prem-files/update/$SCRIPT_NAME -O ./scripts/update/$SCRIPT_NAME
    chmod +x ./scripts/update/$SCRIPT_NAME
    log "$clr_grn" "$script обновлен"

    if [[ $SCRIPT_NAME == "update_master.sh" ]]; then
        log "$clr_ylw" "Необходимо запустить update_master.sh заново. ./scripts/update/update_master.sh $1"
    fi
}

check_permissions() {
    # наличие прав на чтение и изменение конфигов
    files=(".env" "docker-compose.yaml" "nginx.conf" "ekd-config/custom.conf" "ekd-config/ekd-file/custom.conf" "scripts")
    rw_files_count="${#files[@]}"
    for file in "${files[@]}"; do
        if ! ([[ -w $file ]] || [[ -r $file ]]); then
            printf "\t%b%b%b\n" "$clr_red" "Невозможно редактирование $file!" "$clr_rst"
            ((rw_files_count--))
        fi
    done

    if [[ $rw_files_count -lt "${#files[@]}" ]]; then
        exit 1
    fi
}

get_docker_credentials
check_for_updates "update_master.sh" "$SCRIPT_VERSION"
check_permissions
check_for_updates "$SCRIPT_NAME" ""
bash ./scripts/update/$SCRIPT_NAME
