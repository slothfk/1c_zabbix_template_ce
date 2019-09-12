#!/bin/bash
#
# 1C Enterprise 8.3 Work Process Managed Locks Info for Zabbix
#
# (c) 2019, Alexey Y. Fedotov
#
# Email: fedotov@kaminsoft.ru
#

LOG_DIR=${1}/zabbix/locks
[[ ! -d ${LOG_DIR} ]] && echo "ОШИБКА: Неверно задан каталог технологического журнала!" && exit 1

LOG_FILE=$(date --date="@$(($(date "+%s") - 3600))" "+%y%m%d%H")

RESULT=($(cat ${LOG_DIR}/rphost_*/${LOG_FILE}.log 2>/dev/null | \
    grep -P "(TDEADLOCK|TTIMEOUT|TLOCK.*,WaitConnections=\d+)" | \
    sed -re "s/[0-9]{2}:[0-9]{2}.[0-9]{6}-//; s/,[a-zA-Z\:]+=/,/g" | \
    awk -F","  'BEGIN {dl=0; to=0; lw=0} { if ($2 == "TDEADLOCK") {dl+=1} \
        else if ($2 == "TTIMEOUT") { to+=1 } \
        else { lw+=$1; lws[$4"->"$6]+=$1; } } \
        END { print lw/1000000":"to":"dl"<nl>"; \
        if ( length(lws) > 0 ) { print "Ожидания на блокировках:<nl>"; \
        for ( i in lws ) { print "> "i" - "lws[i]/1000000" сек.<nl>" } } }'))

echo ${RESULT[*]} | perl -pe 's/<nl>\s?/\n/g'

COUNTERS=${RESULT[0]%<*}

[[ ${COUNTERS##*:} != 0 || ${COUNTERS%%:*} != 0 || $(echo ${COUNTERS} | cut -d: -f2) != 0 ]] && \
    cd ${LOG_DIR} && tar czf ../problem_log/${LOG_FILE}.tgz ./rphost_*/${LOG_FILE}.log && \
    echo "Файлы технологического журнала сохранены (${LOG_DIR%/*}/problem_log/${LOG_FILE}.tgz)"
