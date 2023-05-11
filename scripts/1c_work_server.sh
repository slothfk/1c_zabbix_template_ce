#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (рабочий сервер)
#
# (c) 2019-2023, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

WORK_DIR=$(dirname "${0}" | sed -r 's/\\/\//g; s/^(.{1}):/\/\1/')

# Включить опцию extglob если отключена (используется в 1c_common_module.sh)
shopt -q extglob || shopt -s extglob

source "${WORK_DIR}/1c_common_module.sh" 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

# Коды завершения процедуры архивирования файлов технологического журнала
export DUMP_CODE_0=0   # Архивированение файлов ТЖ выполнено успешно
export DUMP_CODE_1=1   # Файл архива ТЖ уже существует
export DUMP_CODE_2=2   # При архивировании файлов ТЖ возникли ошибки
export DUMP_CODE_3=3   # Не удалось выполнить архивирование ТЖ на удаленом сервере

function check_log_dir {
    [[ ! -d "${1}/zabbix/${2}" ]] && error "Неверно задан каталог технологического журнала!"
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
        *) error "${ERROR_UNKNOWN_PARAM}" ;;
    esac

    put_brack_line

    cat "${LOG_DIR}"/rphost_*/"${LOG_FILE}.log" 2>/dev/null | awk "/CALL,.*(Context|Module)/" | \
	sed -re 's/,Module=(.*),Method=/,Context=ОбщийМодуль.ФоновыйВызов : ОбщийМодуль.\1.Модуль./' | \
        sed -re "s/[0-9]+:[0-9]+.[0-9]+-//; s/,Method=[^,]+//; s/,[a-zA-Z:]+=/,/g" | \
        awk -F, -v mode="${MODE}" '{ if ($4) {count[$4"->"$5]+=1; durations[$4"->"$5]+=$1; \
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
        sort -rn | head -n "${TOP_LIMIT}" | awk -v mode="${MODE}" -F"@" '{ if ( mode == "lazy" ) { print $2 } else { print $0 } }'
}


function get_locks_info {

    STORE_PERIOD=30 # Срок хранения архивов ТЖ, содержащих информацию о проблемах - 30 дней

    WAIT_LIMIT=${1}

    function save_logs {
        if [[ $(echo "${1}" | grep -ic "${HOSTNAME}") -ne 0 ]]; then
            DUMP_RESULT=$(dump_logs "${LOG_DIR}" "${LOG_FILE}")
        else
            DUMP_RESULT=$(zabbix_get -s "${1}" -k 1c.ws.dump_logs["${LOG_DIR}","${LOG_FILE}"] 2>/dev/null)
            [[ -z ${DUMP_RESULT} || ${DUMP_RESULT} -eq ${DUMP_CODE_2} ]] && DUMP_RESULT=${DUMP_CODE_3}
        fi

        [[ ${DUMP_RESULT} -gt 1 ]] && DUMP_TEXT="ОШИБКА: не удалось сохранить файлы технологического журнала!" ||
            DUMP_TEXT="Файлы технологического журнала сохранены (${LOG_DIR%/*}/problem_log/${LOG_DIR##*/}-${LOG_FILE}.tgz)"

        [[ -n ${DUMP_RESULT} ]] && echo "[${1} (${DUMP_RESULT})] ${DUMP_TEXT}" && unset DUMP_RESULT
    }

    echo "lock: $(cat "${LOG_DIR}"/rphost_*/"${LOG_FILE}.log" 2>/dev/null | grep -c ',TLOCK,')"

    read -ar RESULT < <(cat "${LOG_DIR}"/rphost_*/"${LOG_FILE}.log" 2>/dev/null | \
        awk "/(TDEADLOCK|TTIMEOUT|TLOCK.*,WaitConnections=[0-9]+)/" | \
        sed -re "s/[0-9]{2}:[0-9]{2}.[0-9]{6}-//; s/,[a-zA-Z\:]+=/,/g" | \
        awk -F"," -v lts="${WAIT_LIMIT}" 'BEGIN {dl=0; to=0; lw=0} { if ($2 == "TDEADLOCK") {dl+=1} \
            else if ($2 == "TTIMEOUT") { to+=1 } \
            else { lw+=$1; lws[$4"->"$6]+=$1; } } \
            END { print "timeout: "to"<nl>"; print "deadlock: "dl"<nl>"; print "wait: "lw/1000000"<nl>"; \
            if ( lw > 0 ) { print "Ожидания на блокировках (установлен порог "lts" сек):<nl>"; \
            for ( i in lws ) { print "> "i" - "lws[i]/1000000" сек.<nl>" } } }')

    echo "${RESULT[@]}" | perl -pe 's/<nl>\s?/\n/g'

    if [[ "${RESULT[1]%<*}" != 0 || "${RESULT[3]%<*}" != 0 ||
        $( awk -v value="${RESULT[5]%<*}" -v limit="${WAIT_LIMIT}" 'BEGIN { print ( value > limit ) }' ) == 1 ]]; then

        shift; make_ras_params "${@}"

        check_clusters_cache

        for CURRENT_HOST in $( pop_clusters_list ); do
            CLSTR_LIST=${CURRENT_HOST#*#}
            for CURR_CLSTR in ${CLSTR_LIST//;/ }; do
                SRV_LIST+=( $(timeout -s HUP "${RAS_TIMEOUT}" rac server list --cluster="${CURR_CLSTR%,*}" \
                    ${RAS_AUTH} "${CURRENT_HOST%#*}" 2>/dev/null| grep agent-host | sort -u | \
                    sed -r "s/.*: (.*)$/\1/; s/\"//g") )
            done
        done

    fi

    export -f dump_logs
    execute_tasks save_logs $(echo "${SRV_LIST[@]}" | perl -pe 's/ /\n/g' | sort -u)

    find "${LOG_DIR%/*}/problem_log/" -mtime +${STORE_PERIOD} -name "*.tgz" -delete 2>/dev/null
}

function get_excps_info {

    for PROCESS in "${PROCESS_NAMES[@]}"; do
        EXCP_COUNT=$(cat "${LOG_DIR}"/"${PROCESS}"_*/"${LOG_FILE}.log" 2>/dev/null | grep -c ",EXCP,")
        echo "${PROCESS}: $([[ -n ${EXCP_COUNT} ]] && echo "${EXCP_COUNT}" || echo 0)"
    done
}

function get_memory_counts {

    RPHOST_PID_HASH="${TMPDIR}/1c_rphost_pid_hash"

    if [[ -z "${IS_WINDOWS}" ]]; then
        ps -hwwp "$( pgrep -d, 'ragent|rphost|rmngr' )" -o comm,pid,rss,cmd -k pid |
            sed -re 's/^([^ ]+) +([0-9]+) +([0-9]+) +/\1,\2,\3,/'
    else
        wmic path win32_process where "caption like 'ragent%' or caption like 'rmngr%' or caption like 'rphost%'" \
            get caption,processid,workingsetsize,commandline /format:csv |
            sed -re 's/^[^,]+,([^,]+),([^,]+),([^,]+),(.*)/\1,\3,\4,\2/'
    fi | awk -F, -v mem_in_kb="${IS_WINDOWS:-1024}" -v pid_hash="$( cat "${RPHOST_PID_HASH}" 2>/dev/null )" \
        '/.*,[0-9]+,[0-9]+/ {
            proc_name[$1]=gensub(/[.].+/,"","g",$1)
            proc_pids[$1][$2]
            proc[$1,"memory"]+=$3 
            } END {
                for ( pn in proc_name ) { 
                    proc_flag=""; pid_list=""
                    switch (pn) {
                        case /ragent.*/:
                            if ($4 ~ /(\/|-)debug(\s|$)/ ) proc_flag=1; else proc_flag=0
                            break
                        case /rphost.*/:
                            for (i in proc_pids[pn]) pid_list=pid_list?pid_list","i:i
                            hash_command="echo "pid_list" | md5sum | sed \"s/ .*//\""
                            (hash_command | getline new_hash) > 0
                            close(hash_command)
                            if ( pid_hash == new_hash ) { proc_flag=0 } else { proc_flag=1 }
                            print new_hash > "'"${RPHOST_PID_HASH}"'"
                            break
                    }
                    print proc_name[pn]":",length(proc_pids[pn]),proc[pn,"memory"]*mem_in_kb,proc_flag
                }
            }'

}

# Архивирование файлов ТЖ с именем ${2} из каталога ${1} в problem_log
function dump_logs {
    # TODO: Проверка наличия каталога problem_log и возможности записи в него

    if [[ -f ${1%/*}/problem_log/${1##*/}-${2}.tgz ]]; then
        DUMP_RESULT=${DUMP_CODE_1}
    else
        cd "${1}" 2>/dev/null && tar czf "../problem_log/${1##*/}-${2}.tgz" ./rphost_*/"${2}".log && \
        DUMP_RESULT=${DUMP_CODE_0} || DUMP_RESULT=${DUMP_CODE_2}
    fi

    echo "${DUMP_RESULT}"

}

function get_physical_memory {
    if [[ -z ${IS_WINDOWS} ]]; then
        free -b | grep -m1 "^[^ ]" | awk '{ print $2 }'
    else
        wmic computersystem get totalphysicalmemory | awk "/^[0-9]/"
    fi
}

function get_available_perfomance {

    check_clusters_cache

    ( execute_tasks get_processes_perfomance $( pop_clusters_list ) ) | grep -i "${HOSTNAME}" |
        awk -F: '{ apc+=1; aps+=$2 } END { if ( apc > 0) { print aps/apc } else { print "0" } }'

}

case ${1} in
    calls | locks | excps) check_log_dir "${2}" "${1}";
        export LOG_FILE=$(date --date="last hour" "+%y%m%d%H");
        export LOG_DIR="${2%/}/zabbix/${1}" ;;&
    excps) PROCESS_NAMES=(ragent rmngr rphost) ;;&
    calls) shift 2; get_calls_info "${@}" ;;
    locks) shift 2; get_locks_info "${@}" ;;
    excps) shift 2; get_excps_info "${@}" ;;
    memory) get_memory_counts ;;
    ram) get_physical_memory ;;
    dump_logs) shift; dump_logs "${@}" ;;
    perfomance) shift; make_ras_params "${@}"; get_available_perfomance ;;
    *) error "${ERROR_UNKNOWN_MODE}" ;;
esac

