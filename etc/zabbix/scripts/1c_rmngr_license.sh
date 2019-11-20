#!/bin/bash
#
# 1C Enterprise 8.3 Software License Utilization Info for Zabbix
#
# (c) 2019, Alexey Y. Fedotov
#
# Email: fedotov@kaminsoft.ru
#

#LIC_DIR="/var/1C/licenses"

source ${0%/*}/1c_common_vars.sh 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_vars.sh!" ; exit 1; }

CLSTR_CACHE="${CACHE_DIR}/1c.rmngr.lst"
LIC_COUNT_CACHE="${CACHE_DIR}/1c_rmngr_license_${$}.log"

[[ ! -d ${CACHE_DIR} ]] && mkdir -p ${CACHE_DIR}

function licenses_summary {

    [[ ! -f /etc/1C/1CE/ring-commands.cfg ]] &&  echo "ОШИБКА: Не установлена утилита ring!" && exit 1 
    LIC_TOOL=$(grep license-tools /etc/1C/1CE/ring-commands.cfg | cut -d: -f2)
    
    [[ -z ${LIC_TOOL} ]] && echo "ОШИБКА: Не установлена утилита license-tools!" && exit 1

    RING_TOOL=${LIC_TOOL%\/*\/*}"/*ring*/ring"
    
    LIC_LIST=$(${RING_TOOL} license list | sed 's/(.*//')
    LIC_COUNT=0; LIC_USERS=0

    if [[ -z ${TM_AVAILABLE} ]]; then
       for CURR_LIC in ${LIC_LIST} 
        do
            license_info ${CURR_LIC}
        done
    else
        TASKS_LIST=(${LIC_LIST[*]})
        tasks_manager license_info 0
    fi

    while read -r CURR_COUNT
    do
        ((LIC_COUNT++))
        ((LIC_USERS+=${CURR_COUNT}))
    done < ${LIC_COUNT_CACHE}

    echo ${LIC_COUNT}:${LIC_USERS}

}

function license_info {
    LIC_INFO=$(${RING_TOOL} license info --name ${1} | grep -Pe 'Описание.*на \d+ .*' | perl -pe 's/.*на (\d+) .*/\1/;')
    [[ -n ${LIC_INFO} ]] && echo ${LIC_INFO} >> ${LIC_COUNT_CACHE}
}

function get_cluster_uuid {
    CURR_CLSTR=$( timeout ${RAS_TIMEOUT} rac cluster list ${1%%:*}:${RAS_PORT} |grep -Pe '(cluster|name|port)' | \
        perl -pe 's/[ "]//g; s/^name:(.*)$/\1\n/; s/^cluster:(.*)/\1,/; s/^port:(.*)/\1,/; s/\n//' | \
        grep -Pe ${1##*:} | perl -pe 's/(.*,)\d+,(.*)/\1\2/; s/\n/;/' )
    echo ${1%%:*}:${CURR_CLSTR} >> ${CLSTR_CACHE}
}

function get_license_counts {
    CLSTR_LIST=${1##*:}
    for CURR_CLSTR in ${CLSTR_LIST//;/ }
    do
        timeout ${RAS_TIMEOUT} rac session list --licenses --cluster=${CURR_CLSTR%,*} ${1%%:*}:${RAS_PORT} 2>/dev/null | \
            grep -Pe "(user-name|rmngr-address|app-id)" | \
            perl -pe 's/ //g; s/\n/|/; s/rmngr-address:(\"(.*)\"|)\||/\2/; s/app-id://; s/user-name:/\n/;' | \
            awk -F"|" -v hostname=$(hostname -s) -v cluster=${CURR_CLSTR#*,} 'BEGIN { sc=0; hc=0; cc=0; wc=0 } \
                { if ($1 != "") { sc+=1; uc[$1]; if ( tolower($3) == tolower(hostname) ) { hc+=1 } \
                if ($2 == "WebClient") { wc+=1 } if ($3 == "") { cc+=1 } } } \
                END {print cluster":"hc":"length(uc)":"sc":"cc":"wc }' >> ${LIC_COUNT_CACHE}
    done
}

function used_license {

    RMNGR_LIST=( $(pgrep -xa rmngr | sed -re 's/.*-(reg|)port ([0-9]+) .*/\0|\2/; s/.*-(reg|)host /|/; s/ .*\|/:/; s/^(\||[^|^:]+)//' | \
        sort | uniq | awk -F: '{ if ( clstr_list[$1]== "" ) { clstr_list[$1]=$2 } else { clstr_list[$1]=clstr_list[$1]"|"$2 } } \
        END { for ( i in clstr_list ) { print i":"clstr_list[i]} }' ) )
    SRV_LIST=()

    [[ -n ${1} ]] && RAS_PORT=${1}

    if [[ ! -e ${CLSTR_CACHE} || 
        ${#RMNGR_LIST[*]} -ne $(wc -l ${CLSTR_CACHE} | cut -f1 -d" ") ||
        $(date -r ${CLSTR_CACHE} "+%s") -lt $(date -d "-1 hour" "+%s") ]]; then

        cat /dev/null > ${CLSTR_CACHE}
        if [[ -z ${TM_AVAILABLE} ]]; then
            for CURR_RMNGR in ${RMNGR_LIST[*]}
            do
                get_cluster_uuid ${CURR_RMNGR}
            done
        else
            TASKS_LIST=(${RMNGR_LIST[*]})
            tasks_manager get_cluster_uuid 0
        fi
    fi

    while read -r CURR_SRV
    do
        SRV_LIST+=(${CURR_SRV})
    done < ${CLSTR_CACHE}

    if [[ -z ${TM_AVAILABLE} ]]; then
        for CURR_SRV in ${SRV_LIST[*]}
        do
            get_license_counts ${CURR_SRV}
        done
    else
        TASKS_LIST=(${SRV_LIST[*]})
        tasks_manager get_license_counts 0
    fi

    awk -F: 'BEGIN {ul=0; as=0; cl=0; uu=0; wc=0} { print $0; ul+=$2; uu+=$3; as+=$4; cl+=$5; wc+=$6; } \
       END { print "summary:"ul":"uu":"as":"cl":"wc }' ${LIC_COUNT_CACHE};

}

function get_clusters_list {

    [[ ! -f ${CLSTR_CACHE} ]] && echo "ОШИБКА: Не найден файл списка кластеров!" && exit 1

    cut -f2 -d: ${CLSTR_CACHE} | perl -pe 's/;[^\n]/\n/; s/;//' | \
        awk 'BEGIN {FS=","; print "{\"data\":[" } \
            {print "{\"{#CLSTR_UUID}\":\""$1"\",\"{#CLSTR_NAME}\":\""$2"\"}," } \
            END { print "]}" }' | \
        perl -pe 's/\n//;' | perl -pe 's/(.*),]}/\1]}\n/'

}

case ${1} in
    info) licenses_summary ;;
    used) used_license $2 ;;
    clusters) get_clusters_list ;;
    *) echo "ОШИБКА: Неверный режим работы скрипта!"; exit 1;;
esac

[[ -f ${LIC_COUNT_CACHE} ]] && rm ${LIC_COUNT_CACHE}
