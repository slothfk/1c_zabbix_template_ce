#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (центральный сервер)
#
# (c) 2020, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

source ${0%/*}/1c_common_module.sh 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

function get_infobase_status {
    curl -u "${2}:${3}" --header "SOAPAction: http://www.1c.ru/SSL/RemoteControl_1_0_0_1#RemoteControl:GetCurrentState" \
        -d '<env:Envelope xmlns:env="http://www.w3.org/2003/05/soap-envelope"
        xmlns:ns1="http://www.1c.ru/SSL/RemoteControl_1_0_0_1"><env:Body><ns1:GetCurrentState/>
        </env:Body></env:Envelope>' ${1}/ws/RemoteControl | perl -pe 's/.*m:return[^>]+>(\w+)<.*/\1/'
}

function get_clusters_uid {
    timeout -s HUP ${RAS_TIMEOUT} rac cluster list ${1}:${RAS_PORT} | grep -Pe '(cluster|name)' | \
        perl -pe 's/[ "]//g; s/^name:(.*)$/\1\n/; s/^cluster:(.*)/\1,/; s/\n//' | perl -pe 's/\n/;/' 
}

function get_infobases_list {
    [[ -n ${1} ]] && RAS_PORT=${1}
    CLUSTERS_LIST=$(get_clusters_uid localhost:${RAS_PORT})

    BASE_INFO='{"data":[ '
    for CURRENT_CLUSTER in ${CLUSTERS_LIST//;/ }; do
        BASE_LIST=$(timeout -s HUP ${RAS_TIMEOUT} rac infobase summary list \
            --cluster ${CURRENT_CLUSTER%,*} localhost:${RAS_PORT} | grep -Pe '(infobase|name)' | \
            perl -pe 's/[ "]//g; s/^name:(.*)$/\1\n/; s/^infobase:(.*)/\1,/; s/\n//' | perl -pe 's/\n/;/' )
        for CURRENT_BASE in ${BASE_LIST//;/ }; do
            BASE_INFO+="{ \"{#CLSTR_UUID}\":\"${CURRENT_CLUSTER%,*}\",\"{#CLSTR_NAME}\":\"${CURRENT_CLUSTER#*,}\",\"{#IB_UUID}\":\"${CURRENT_BASE%,*}\",\"{#IB_NAME}\":\"${CURRENT_BASE#*,}\" }, "
        done
    done
    echo "${BASE_INFO%, } ]}"
}

case ${1} in
    ib_status) shift; get_infobase_status ${@} ;;
    infobases) get_infobases_list ${2} ;;
    *) echo "ОШИБКА: Неизвестный режим работы скрипта!"; exit 1;;
esac

