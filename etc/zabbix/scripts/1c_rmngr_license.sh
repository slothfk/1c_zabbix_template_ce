#!/bin/bash
#
# 1C Enterprise 8.3 Software License Utilization Info for Zabbix
#
# (c) 2019, Alexey Y. Fedotov
#
# Email: fedotov@kaminsoft.ru
#

#LIC_DIR="/var/1C/licenses"
TM_MODULE="1c_common_ts.sh"

CACHE_DIR="/var/tmp/1C"
CLSTR_CACHE="${CACHE_DIR}/1c.rmngr.lst"
LIC_COUNT_CACHE="${CACHE_DIR}/1c.license.log"

RAS_PORT=1545

G_BINDIR=$(ls -d /opt/1C/v8*/x*)

[[ ! -d ${CACHE_DIR} ]] && mkdir -p ${CACHE_DIR}

[[ -f ${0%/*}/${TM_MODULE} ]] && source ${0%/*}/${TM_MODULE} 2>/dev/null && TM_AVAILABLE=1

function licenses_info {

    [[ ! -f /etc/1C/1CE/ring-commands.cfg ]] && echo "ОШИБКА: Не установлена утилита ring!" && exit 1
    LIC_TOOL=$(grep license-tools /etc/1C/1CE/ring-commands.cfg | cut -d: -f2)
    
    [[ -z ${LIC_TOOL} ]] && echo "ОШИБКА: Не установлена утилита license-tools!" && exit 1

    RING_TOOL=${LIC_TOOL%\/*\/*}"/*ring*/ring"
    
    #[[ -n ${2} ]] && LIC_DIR=${2}

    LIC_LIST=$(${RING_TOOL} license list | sed 's/(.*//')
    LIC_COUNT=0
    LIC_USERS=0

    for CURR_LIC in ${LIC_LIST} 
    do
        LIC_INFO=$(${RING_TOOL} license info --name ${CURR_LIC} | grep -Pe "Описание.*на \d+ .*" | perl -pe "s/.*на (\d+) .*/\1/;")
        if [[ -n ${LIC_INFO} ]] ; then
            LIC_COUNT=$((${LIC_COUNT}+1))
            LIC_USERS=$((${LIC_USERS}+${LIC_INFO}))
        fi 
    done

    echo ${LIC_COUNT}:${LIC_USERS}

}

function get_cluster_uuid {
    CURR_CLSTR=$(${G_BINDIR}/rac cluster list ${1}:${RAS_PORT} | grep cluster | sed 's/.*: //')
    echo ${1}:${CURR_CLSTR// /,} >> ${CLSTR_CACHE}
}

function get_license_counts {
    CLSTR_LIST=${1##*:}
    for CURR_CLSTR in ${CLSTR_LIST//,/ }
    do
        ${G_BINDIR}/rac session list --licenses --cluster=${CURR_CLSTR} ${1%%:*}:${RAS_PORT} 2>/dev/null | \
            grep -Pe "(user-name|rmngr-address|app-id)" | \
            perl -pe 's/ //g; s/\n/|/; s/rmngr-address:(\"(.*)\"|)\||/\2/; s/app-id://; s/user-name:/\n/;' | \
            awk -F"|" -v hostname=$(hostname -s) 'BEGIN { sc=0; hc=0; cc=0; wc=0 } \
                { if ($1 != "") { sc+=1; uc[$1]; if ( tolower($3) == tolower(hostname) ) { hc+=1 } \
                if ($2 == "WebClient") { wc+=1 } if ($3 == "") { cc+=1 } } } \
                END {print "UL:"hc; print "AS:"sc; print "WC:"wc; \
                print "UU:"length(uc); print "CL:"cc }' >> ${LIC_COUNT_CACHE}
    done
}

function used_license {

    RMNGR_LIST=($(pgrep -xa rmngr | sed -re "s/.*-(reg|)host /|/; s/ -(regport|range).*//; s/(^\||.*)(.*)/\2/; s/^$/$(hostname)/"))
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

    awk -F: 'BEGIN {ul=0; as=0; cl=0; uu=0; wc=0} { switch ($1) { case "UL": ul+=$2; \
        break; case "AS": as+=$2; break; case "UU": uu+=$2; break; case "WC": wc+=$2; break; \
        case "CL": cl+=$2; } } END { print ul":"uu":"as":"cl":"wc }' ${LIC_COUNT_CACHE};

    rm ${LIC_COUNT_CACHE}

}

case ${1} in
    info) licenses_info ;;
    used) used_license $2 ;;
    *) echo "ОШИБКА: Неверный режим работы скрипта!"; exit 1;;
esac