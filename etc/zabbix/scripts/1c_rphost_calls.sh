#!/bin/bash
#
# 1C Enterprise 8.3 Work Process Calls Info for Zabbix
#
# (c) 2019, Alexey Y. Fedotov
#
# Email: fedotov@kaminsoft.ru
#

LOG_DIR=${1}/zabbix/calls
[[ ! -d ${LOG_DIR} ]] && echo "ОШИБКА: Неверно задан каталог технологического журнала!" && exit 1

LOG_FILE=$(date --date="@$(($(date "+%s") - 3600))" "+%y%m%d%H")

MODE=${2}

[[ -n ${3} ]] && TOP_LIMIT=${3} || TOP_LIMIT=25

function brack_line {
    [[ -n ${1} ]] && LIMIT=${1} || LIMIT=80;
    for (( i=0; i < ${LIMIT}; i++ )) {
        echo -n "-"
    }
    echo
}

case ${MODE} in
    count) echo "Кол-во | Длит-ть,с | СрДл-ть,мс | Контекст";;
    cpu) echo "Процессор,с (%) | Длит-ть,с | Кол-во | СрДл-ть,мс | Контекст";;
    duration) echo "Длительность,с (%) | Кол-во | СрДл-ть,мс | Процессор | Контекст";;
    *) echo "ОШИБКА: Неверный режим работы скрипта!"; exit 1 ;;
esac
brack_line

cat ${LOG_DIR}/rphost_*/${LOG_FILE}.log 2>/dev/null | \
    sed -re "s/[0-9]+:[0-9]+.[0-9]+-//; s/,[a-zA-Z:]+=/,/g" | \
    awk -F, -v mode=${MODE} '{ if ($4) {count[$4"->"$5]+=1; durations[$4"->"$5]+=$1; \
        cpus[$4"->"$5]+=$9; duration[$4]+=$1; cpu[$4]+=$9; } } \
    END { for ( i in count ) { \
        if ( mode == "count" ) { printf "%6d | %9.2f | %10.2f | %s\n", count[i], \
            durations[i]/1000000, durations[i]/count[i]/1000, i } \
        else if ( mode == "cpu" ) { printf "%8.2f (%4.1f) | %9.2f | %6d | %10.2f | %s\n", \
            cpus[i]/1000000, cpus[i]/cpu[substr(i,0,index(i,"->")-1)]*100, durations[i]/1000000, count[i], durations[i]/count[i]/1000, i }  \
        else if ( mode == "duration" ) { printf "%11.2f (%4.1f) | %6d | %10.2f | %9.2f | %s\n", \
            durations[i]/1000000, durations[i]/duration[substr(i,0,index(i, "->")-1)]*100, count[i], durations[i]/count[i]/1000, cpus[i]/1000000, i } \
        } }' | \
    sort -rn | head -n ${TOP_LIMIT} | awk -v mode=${MODE} -F"@" '{ if ( mode == "lazy" ) { print $2 } else { print $0 } }'
