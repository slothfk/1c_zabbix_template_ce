#!/bin/bash
#
# 1C Enterprise 8.3 Software License Utilization Info for Zabbix
#
# (c) 2019, Alexey Y. Fedotov
#
# Email: fedotov@kaminsoft.ru
#

#LIC_DIR="/var/1C/licenses"
CACHE_DIR="/var/tmp/1C"
RAS_PORT=1545

[[ ! -d ${CACHE_DIR} ]] && mkdir -p ${CACHE_DIR}

function licenses_info {

    [[ ! -f /etc/1C/1CE/ring-commands.cfg ]] && echo "ОШИБКА: Не установлена утилита ring!" && exit 1
    LIC_TOOL=$(grep license-tools /etc/1C/1CE/ring-commands.cfg | cut -d: -f2)
    
    [[ -z ${LIC_TOOL} ]] && echo "ОШИБКА: Не установлена утилита license-tools!" && exit 1

    RING_TOOL=${LIC_TOOL%\/*\/*}"/ring/ring"
    
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

function used_license {

    G_BINDIR=$(ls -d /opt/1C/v8*/x*)
    RMNGR_LIST=($(pgrep -xa rmngr | sed -re "s/.*-(reg|)host /|/; s/ -(regport|range).*//; s/(^\||.*)(.*)/\2/; s/^$/$(hostname)/"))
    CACHE_FILE="${CACHE_DIR}/1c.rmngr.lst"
    SRV_LIST=()
    USED_LIC=0; ALL_SESS=0; UNIQ_USR=0

    [[ -n ${1} ]] && RAS_PORT=${1}

    if [[ ! -e ${CACHE_FILE} || 
        ${#RMNGR_LIST[*]} -ne $(wc -l ${CACHE_FILE} | cut -f1 -d" ") ||
        $(date -r ${CACHE_FILE} "+%s") -lt $(date -d "-1 hour" "+%s") ]]; then

        cat /dev/null > ${CACHE_FILE}
        for CURR_RMNGR in ${RMNGR_LIST[*]}
        do
            CURR_CLSTR=$(${G_BINDIR}/rac cluster list ${CURR_RMNGR}:${RAS_PORT} | grep cluster | sed 's/.*: //')
            SRV_LIST+=(${CURR_RMNGR}:${CURR_CLSTR// /,})
            echo ${SRV_LIST[${#SRV_LIST[*]}-1]} >> ${CACHE_FILE}
        done
    else
        while read -r CURR_SRV
        do
            SRV_LIST+=(${CURR_SRV})
        done < ${CACHE_FILE}
    fi

    for CURR_SRV in ${SRV_LIST[*]}
    do
        CLSTR_LIST=${CURR_SRV##*:}
        for CURR_CLSTR in ${CLSTR_LIST//,/ }
        do
             CURR_COUNTS=($(${G_BINDIR}/rac session list --licenses --cluster=${CURR_CLSTR} ${CURR_SRV%%:*}:${RAS_PORT} 2>/dev/null | \
                grep -Pe "(user-name|rmngr-address)" | perl -pe 's/ //g; s/\n/|/; s/rmngr-address:(\"(.*)\"|)\||/\2/; s/(user-name:)/\n/' | \
                awk -F"|" -v hostname=$(hostname) 'BEGIN {sc=0; hc=0; cc=0; uc } { if ($1 != "") {sc+=1; uc[$1]; \
                        if (tolower($2) == tolower(hostname)) {hc+=1;} } } END {print hc" "sc" "length(uc) }'))
            USED_LIC=$(( ${USED_LIC} + ${CURR_COUNTS[0]} ))
            ALL_SESS=$(( ${ALL_SESS} + ${CURR_COUNTS[1]} ))
            UNIQ_USR=$(( ${UNIQ_USR} + ${CURR_COUNTS[2]} ))
        done
    done

    echo ${USED_LIC}:${UNIQ_USR}:${ALL_SESS}

}

case ${1} in
    info) licenses_info ;;
    used) used_license $2 ;;
    *) echo "ОШИБКА: Неверный режим работы скрипта!"; exit 1;;
esac