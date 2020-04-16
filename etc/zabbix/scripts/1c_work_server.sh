#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (рабочий сервер)
#
# (c) 2019-2020, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

source ${0%/*}/1c_common_module.sh 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

function check_log_dir {
    [[ ! -d "${1}/zabbix/${2}" ]] && echo "ОШИБКА: Неверно задан каталог технологического журнала!" && exit 1
}

function get_calls_info {

    MODE=${1}

    [[ -n ${2} ]] && TOP_LIMIT=${2} || TOP_LIMIT=25

    case ${MODE} in
        count) echo "Кол-во | Длит-ть,с | СрДл-ть,мс | Контекст";;
        cpu) echo "Процессор,с (%) | Длит-ть,с | Кол-во | СрДл-ть,мс | Контекст";;
        duration) echo "Длительность,с (%) | Кол-во | СрДл-ть,мс | Процессор | Контекст";;
        lazy) echo "Длит-ть,с | Кол-во | СрДл-ть,мс | Процессор | Контекст";;
        dur_avg) echo "СрДл-ть,с | Длит-ть,с | Кол-во | Процессор | Контекст";;
        memory) echo "Память,МБ | СрДл-ть,мс | СрПр-ор,мс | Кол-во | Контекст";;
        iobytes) echo "Объем IO,МБ | Длит-ть,с | Процессор | Кол-во | Контекст";;
        *) echo "ОШИБКА: Некорректный параметр для данного режима работы скрипта!"; exit 1 ;;
    esac

    put_brack_line

    cat ${LOG_DIR}/rphost_*/${LOG_FILE}.log 2>/dev/null | grep -Pe "CALL,.*(Context|Module)" | \
	sed -re 's/,Module=(.*),Method=/,Context=ОбщийМодуль.ФоновыйВызов : ОбщийМодуль.\1.Модуль./' | \
        sed -re "s/[0-9]+:[0-9]+.[0-9]+-//; s/,Method=[^,]+//; s/,[a-zA-Z:]+=/,/g" | \
        awk -F, -v mode=${MODE} '{ if ($4) {count[$4"->"$5]+=1; durations[$4"->"$5]+=$1; \
            cpus[$4"->"$5]+=$9; iobytes[$4"->"$5]+=$7+$8; duration[$4]+=$1; cpu[$4]+=$9; \
            if ( mempeak[$4"->"$5] < $6 ) { mempeak[$4"->"$5]=$6; } } } \
        END { for ( i in count ) { \
            if ( mode == "count" ) { printf "%6d | %9.2f | %10.2f | %s\n", count[i], \
                durations[i]/1000000, durations[i]/count[i]/1000, i } \
            else if ( mode == "cpu" ) { printf "%8.2f (%4.1f) | %9.2f | %6d | %10.2f | %s\n", \
                cpus[i]/1000000, cpus[i]/cpu[substr(i,0,index(i,"->")-1)]*100, durations[i]/1000000, count[i], durations[i]/count[i]/1000, i }  \
            else if ( mode == "lazy" ) { printf "%f@%9.2f | %6d | %10.2f | %9.2f | %s\n", \
                durations[i]/cpus[i], durations[i]/1000000, count[i], durations[i]/count[i]/1000, cpus[i]/1000000, i }  \
            else if ( mode == "dur_avg" ) { printf "%9.2f | %9.2f | %6d | %9.2f | %s\n", \
                durations[i]/count[i]/1000000, durations[i]/1000000, count[i], cpus[i]/1000000, i }  \
            else if ( mode == "duration" ) { printf "%11.2f (%4.1f) | %6d | %10.2f | %9.2f | %s\n", \
                durations[i]/1000000, durations[i]/duration[substr(i,0,index(i, "->")-1)]*100, count[i], durations[i]/count[i]/1000, cpus[i]/1000000, i } \
            else if ( mode == "memory" ) { printf "%9.2f | %10.2f | %10.2f | %6d | %s\n", \
                mempeak[i]/1024/1024, durations[i]/count[i]/1000, cpus[i]/count[i]/1000, count[i], i } \
            else if ( mode == "iobytes" ) { printf "%11.2f | %9.2f | %9.2f | %6d | %s\n", \
                iobytes[i]/1024/1024, durations[i]/1000000, cpus[i]/1000000, count[i], i } \
            } }' | \
        sort -rn | head -n ${TOP_LIMIT} | awk -v mode=${MODE} -F"@" '{ if ( mode == "lazy" ) { print $2 } else { print $0 } }'
}


function get_locks_info {
    DUMP_CODE_0=0   # Архивированение файлов ТЖ выполнено успешно
    DUMP_CODE_1=1   # Файл архива ТЖ уже существует
    DUMP_CODE_2=2   # Не удалось выполнить архивирование ТЖ на текущем сервере
    DUMP_CODE_3=3   # Не удалось выполнить архивирование ТЖ на удаленом сервере

    STORE_PERIOD=30 # Срок хранения архивов ТЖ, содержащих информацию о проблемах - 30 дней

    WAIT_LIMIT=${1}

    function save_logs {
        if [[ $(echo ${1} | grep -ic ${HOSTNAME}) -ne 0 ]]; then
            if [[ -f ${LOG_DIR%/*}/problem_log/${LOG_FILE}.tgz ]]; then
                DUMP_RESULT=${DUMP_CODE_1}
            else
                cd ${LOG_DIR} && tar czf ../problem_log/${LOG_FILE}.tgz ./rphost_*/${LOG_FILE}.log && \
                DUMP_RESULT=${DUMP_CODE_0} || DUMP_RESULT=${DUMP_CODE_2}
            fi
        else
            zabbix_get -s ${1} -k 1c.ws.locks[${LOG_DIR%/zabbix/*},${WAIT_LIMIT},${RAS_PORT},dump] 2>/dev/null || \
                DUMP_RESULT=${DUMP_CODE_3}
        fi

        [[ ${DUMP_RESULT} -gt 1 ]] && DUMP_TEXT="ОШИБКА: не удалось сохранить файлы технологического журнала!" ||
            DUMP_TEXT="Файлы технологического журнала сохранены (${LOG_DIR%/*}/problem_log/${LOG_FILE}.tgz)"

        [[ -n ${DUMP_RESULT} ]] && echo "[${1} (${DUMP_RESULT})] ${DUMP_TEXT}" && unset DUMP_RESULT
    }

    if [[ ${3} != "dump" ]]; then

        [[ -n ${2} ]] && RAS_PORT=${2}

        RMNGR_LIST=($(pgrep -xa rphost | sed -re "s/.*-reghost //; s/ -regport.*//;" | sort | uniq))

        RESULT=($(cat ${LOG_DIR}/rphost_*/${LOG_FILE}.log 2>/dev/null | \
            grep -P "(TDEADLOCK|TTIMEOUT|TLOCK.*,WaitConnections=\d+)" | \
            sed -re "s/[0-9]{2}:[0-9]{2}.[0-9]{6}-//; s/,[a-zA-Z\:]+=/,/g" | \
            awk -F"," -v lts=${WAIT_LIMIT} 'BEGIN {dl=0; to=0; lw=0} { if ($2 == "TDEADLOCK") {dl+=1} \
                else if ($2 == "TTIMEOUT") { to+=1 } \
                else { lw+=$1; lws[$4"->"$6]+=$1; } } \
                END { print lw/1000000":"to":"dl"<nl>"; \
                if ( length(lws) > 0 ) { print "Ожидания на блокировках (установлен порог "lts" сек):<nl>"; \
                for ( i in lws ) { print "> "i" - "lws[i]/1000000" сек.<nl>" } } }'))

        echo ${RESULT[@]} | perl -pe 's/<nl>\s?/\n/g'

        COUNTERS=${RESULT[0]%<*}

        if [[ ${COUNTERS##*:} != 0 || $(echo "${COUNTERS%%:*} > ${WAIT_LIMIT}" | bc) != 0 || $(echo ${COUNTERS} | cut -d: -f2) != 0 ]]; then

            for CURR_RMNGR in ${RMNGR_LIST[@]}; do
                CURR_CLSTR=$(timeout -s HUP ${RAS_TIMEOUT} rac cluster list ${CURR_RMNGR}:${RAS_PORT} 2>/dev/null | grep cluster | sed 's/.*: //')
                CLSTR_LIST+=(${CURR_RMNGR}:${CURR_CLSTR// /,})
            done

            for CURR_CLSTR in ${CLSTR_LIST[@]}; do
                CURR_LIST=( $(timeout -s HUP ${RAS_TIMEOUT} rac server list --cluster=${CURR_CLSTR##*:} ${CURR_CLSTR%%:*}:${RAS_PORT} 2>/dev/null|\
                    grep agent-host | uniq | perl -pe "s/.*:/:/; s/( |\n)//g;" | sed -e "s/^://; s/$/\n/;") )
                [[ $(echo ${CURR_LIST} | grep -ic ${HOSTNAME}) -ne 0 ]] && [[ $(echo ${RPHOST_LIST[@]} | grep -ic ${CURR_LIST}) -eq 0 ]] && \
                    RPHOST_LIST+=(${CURR_LIST})
            done

        fi

    else
        RPHOST_LIST=(${HOSTNAME})
    fi

    for CURR_LIST in ${RPHOST_LIST[@]}; do
        execute_tasks save_logs ${CURR_LIST//:/ }
    done

    find ${LOG_DIR%/*}/problem_log/ -mtime +${STORE_PERIOD} -name "*.tgz" -delete
}

function get_excps_info {
    for PROCESS in ${PROCESS_NAMES[@]}; do
        EXCP_COUNT=$(cat ${LOG_DIR}/${PROCESS}_*/${LOG_FILE}.log 2>/dev/null | grep -c ",EXCP,")
        echo ${PROCESS}: $([[ -n ${EXCP_COUNT} ]] && echo ${EXCP_COUNT} || echo 0)
    done
}

function get_memory_counts {

    MEMORY_PAGE_SIZE=$(getconf PAGE_SIZE)
    RPHOST_PID_HASH="${CACHE_DIR}/1c_rphost_pid_hash"

    for PROCESS in ${PROCESS_NAMES[@]}; do
        PROCESS_MEMORY=0
        PID_LIST=$(pgrep -xd, ${PROCESS})
        for CURRENT_PID in ${PID_LIST//,/ }; do
            (( PROCESS_MEMORY+=$(cut -f2 -d" " /proc/${CURRENT_PID}/statm)*${MEMORY_PAGE_SIZE} )) ;
        done
        echo ${PROCESS}: $(echo ${PID_LIST//,/ } | wc -w) ${PROCESS_MEMORY}\
            $(if [[ ${PROCESS} == "rphost" ]]; then 
                RPHOST_OLD_HASH=$(cat ${RPHOST_PID_HASH} 2>/dev/null);
                echo ${PID_LIST} | md5sum | cut -f1 -d\  > ${RPHOST_PID_HASH};
                [[ ${RPHOST_OLD_HASH} == $(cat ${RPHOST_PID_HASH}) ]] ; echo $?; fi)
    done

}

case ${1} in
    calls | locks | excps) check_log_dir ${2} ${1};
        LOG_FILE=$(date --date="last hour" "+%y%m%d%H");
        LOG_DIR="${2%/}/zabbix/${1}" ;;&
    memory | excps) PROCESS_NAMES=(ragent rmngr rphost) ;;&
    calls) shift 2; get_calls_info ${@} ;;
    locks) shift 2; get_locks_info ${@} ;;
    excps) shift 2; get_excps_info ${@} ;;
    memory) get_memory_counts ;;
    ram) free -b | grep -m1 "^[^ ]" | awk '{ print $2 }';;
    *) echo "ОШИБКА: Неизвестный режим работы скрипта!"; exit 1;;
esac

