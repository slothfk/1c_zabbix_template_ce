#!/bin/bash
#
# 1C Enterprise 8.3 Work Process Managed Locks Info for Zabbix
#
# (c) 2019, Alexey Y. Fedotov
#
# Email: fedotov@kaminsoft.ru
#

TM_MODULE="1c_common_tm.sh"

DUMP_CODE_0=0   # Local or Remote copy successful
DUMP_CODE_1=1   # Local copy exists
DUMP_CODE_2=2   # Local copy failed
DUMP_CODE_3=3   # Remote copy failed

STORE_PERIOD=30 # Problem log store period - 30 days

LOG_DIR=${1%/}
LOG_SUBDIR="zabbix/locks"

WAIT_LIMIT=${2}

[[ -f ${0%/*}/${TM_MODULE} ]] && source ${0%/*}/${TM_MODULE} 2>/dev/null && TM_AVAILABLE=1

[[ ! -d ${LOG_DIR}/${LOG_SUBDIR} ]] && echo "ОШИБКА: Неверно задан каталог технологического журнала!" && exit 1

G_BINDIR=$(ls -d /opt/1C/v8*/x*)

LOG_FILE=$(date --date="@$(($(date "+%s") - 3600))" "+%y%m%d%H")

function save_logs {
    if [[ $(echo ${1} | grep -ic $(hostname)) -ne 0 ]]; then
        if [[ -f ${LOG_DIR}/${LOG_SUBDIR%/*}/problem_log/${LOG_FILE}.tgz ]]; then
            DUMP_RESULT=${DUMP_CODE_1}
        else
            cd ${LOG_DIR}/${LOG_SUBDIR} && tar czf ../problem_log/${LOG_FILE}.tgz ./rphost_*/${LOG_FILE}.log && \
            DUMP_RESULT=${DUMP_CODE_0} || DUMP_RESULT=${DUMP_CODE_2}
        fi
    else
        zabbix_get -s ${1} -k 1c.rphost.locks[${LOG_DIR},${WAIT_LIMIT},${RAS_PORT},dump] 2>/dev/null || \
            DUMP_RESULT=${DUMP_CODE_3}
    fi

    [[ ${DUMP_RESULT} -gt 1 ]] && DUMP_TEXT="ОШИБКА: не удалось сохранить файлы технологического журнала!" ||
        DUMP_TEXT="Файлы технологического журнала сохранены (${LOG_DIR}/${LOG_SUBDIR%/*}/problem_log/${LOG_FILE}.tgz)"

    [[ -n ${DUMP_RESULT} ]] && echo "[${1} (${DUMP_RESULT})] ${DUMP_TEXT}" && unset DUMP_RESULT
}

if [[ ${4} != "dump" ]]; then

    [[ -n ${3} ]] && RAS_PORT=${3} || RAS_PORT=1545

    RMNGR_LIST=($(pgrep -xa rphost | sed -re "s/.*-reghost //; s/ -regport.*//;" | uniq))

    RESULT=($(cat ${LOG_DIR}/${LOG_SUBDIR}/rphost_*/${LOG_FILE}.log 2>/dev/null | \
        grep -P "(TDEADLOCK|TTIMEOUT|TLOCK.*,WaitConnections=\d+)" | \
        sed -re "s/[0-9]{2}:[0-9]{2}.[0-9]{6}-//; s/,[a-zA-Z\:]+=/,/g" | \
        awk -F"," -v lts=${WAIT_LIMIT} 'BEGIN {dl=0; to=0; lw=0} { if ($2 == "TDEADLOCK") {dl+=1} \
            else if ($2 == "TTIMEOUT") { to+=1 } \
            else { lw+=$1; lws[$4"->"$6]+=$1; } } \
            END { print lw/1000000":"to":"dl"<nl>"; \
            if ( length(lws) > 0 ) { print "Ожидания на блокировках (установлен порог "lts" сек):<nl>"; \
            for ( i in lws ) { print "> "i" - "lws[i]/1000000" сек.<nl>" } } }'))

    echo ${RESULT[*]} | perl -pe 's/<nl>\s?/\n/g'

    COUNTERS=${RESULT[0]%<*}

    if [[ ${COUNTERS##*:} != 0 || $(echo "${COUNTERS%%:*} > ${WAIT_LIMIT}" | bc) != 0 || $(echo ${COUNTERS} | cut -d: -f2) != 0 ]]; then

        for CURR_RMNGR in ${RMNGR_LIST[*]}
        do
            CURR_CLSTR=$(${G_BINDIR}/rac cluster list ${CURR_RMNGR}:${RAS_PORT} 2>/dev/null | grep cluster | sed 's/.*: //')
            CLSTR_LIST+=(${CURR_RMNGR}:${CURR_CLSTR// /,})
        done

        for CURR_CLSTR in ${CLSTR_LIST[*]}
        do
            CURR_LIST=( $(${G_BINDIR}/rac server list --cluster=${CURR_CLSTR##*:} ${CURR_CLSTR%%:*}:${RAS_PORT} 2>/dev/null|\
                grep agent-host | uniq | perl -pe "s/.*:/:/; s/( |\n)//g;" | sed -e "s/^://; s/$/\n/;") )
            [[ $(echo ${CURR_LIST} | grep -ic $(hostname)) -ne 0 ]] && [[ $(echo ${RPHOST_LIST[*]} | grep -ic ${CURR_LIST}) -eq 0 ]] && \
                RPHOST_LIST+=(${CURR_LIST})
        done

    fi

else
    RPHOST_LIST=($(hostname))
fi

for CURR_LIST in ${RPHOST_LIST[*]}
do
    if [[ -z ${TM_AVAILABLE} ]]; then
        for CURR_RPHOST in ${CURR_LIST//:/ }
        do
            save_logs ${CURR_RPHOST}
        done
    else
        TASKS_LIST=(${CURR_LIST//:/ })
        tasks_manager save_logs 0
    fi
done

find ${LOG_DIR}/${LOG_SUBDIR%/*}/problem_log/ -mtime +${STORE_PERIOD} -name "*.tgz" -exec rm -f {} \;