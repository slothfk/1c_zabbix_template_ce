#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (общие переменные и функции)
#
# (c) 2019-2023, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

# Вывести сообщение об ошибке переданное в аргументе и выйти с кодом 1
function error {
    echo "ОШИБКА: ${1}" >&2 ; exit 1
}

# Системный пользователь для запуска сервера 1С Предприятия
export USR1CV8="usr1cv8"

# Тип операционной системы GNU/Linux или MS Windows
[[ "$(uname -s)" != "Linux" ]] && { IS_WINDOWS=1; export IS_WINDOWS; }

# Имя сервера, используемое в кластере 1С Предприятия
[[ -z ${IS_WINDOWS} ]] && HOSTNAME=$(hostname -s) || HOSTNAME=$(hostname)
export HOSTNAME

# Добавление пути к бинарным файлам 1С Предприятия в переменную PATH
RAC_PATH="$( find /opt/1C/ /opt/1cv8/ /c/Program\ Files*/1cv8/ -regextype awk -regex ".*/rac([.]exe)?" -name "rac*" -print -quit  2>/dev/null )"

if [[ -n ${RAC_PATH} ]]; then
    export PATH="${PATH}:${RAC_PATH%/*}"
else
    error "Не найдена платформа 1С Предприятия!"
fi

# Проверить инициализацию переменной TMPDIR
[[ -z ${TMPDIR} ]] && export TMPDIR="/tmp"

# Файл списка кластеров
export CLSTR_CACHE="${TMPDIR}/1c_clusters_cache"

# Параметры взаимодействия с сервисом RAS
RAS_PORTS="1545"
RAS_TIMEOUT="1.5"
RAS_AUTH=""

# Максимальное число параллельных потоков (половина от числа ядер ЦПУ)
MAX_THREADS=$(( $(nproc) / 2 )) && [[ ${MAX_THREADS} -eq 0 ]] && MAX_THREADS=1 

# Общие для всех скриптов тексты ошибок
export ERROR_UNKNOWN_MODE="Неизвестный режим работы скрипта!"
export ERROR_UNKNOWN_PARAM="Неизвестный параметр для данного режима работы скрипта!"

# Файл списка информационных баз
export IB_CACHE=${TMPDIR}/1c_infobase_cache

# Вывести разделительную строку длинной ${1} из символов ${2}
# По-умолчанию раделительная строка - это 80 символов "-"
function put_brack_line {
    [[ -n ${1} ]] && LIMIT=${1} || LIMIT=80
    [[ -n ${2} ]] && CHAR=${2} || CHAR="-"

    printf "%*s\n" "${LIMIT}" "${CHAR}" | sed "s/ /${CHAR}/g"
}

# Выполнить серию команд ${1} с параметром, являющимся элементом массива ${@}, следующим за ${1}
function execute_tasks {
    [[ ${#@} -le 1 ]] && exit # Если список задач пуст, то выходим
    TASK_CMD=${1}
    shift
    export -f "${TASK_CMD?}"
    echo "${@}" | xargs -d' ' -P${MAX_THREADS} -I task_args bash -c "${TASK_CMD} \${@}" _ task_args
}

# Проверить наличие ring license и вернуть путь до ring
function check_ring_license {
    [[ -z ${IS_WINDOWS} ]] && RING_CONF="/etc/1C/1CE/ring-commands.cfg" ||
         RING_CONF="/C/ProgramData/1C/1CE/ring-commands.cfg"
    [[ ! -f ${RING_CONF} ]] &&  error "Не установлена утилита ring!"
    LIC_TOOL=$(grep license-tools "${RING_CONF}" | sed -r 's/.+file: //; s/\\/\//g; s/^(.{1}):/\/\1/')

    [[ -z ${LIC_TOOL} ]] && error "Не установлена утилита license-tools!"

    ls "${LIC_TOOL%\/*\/*}"/*ring*/ring*
}

# Установить параметры взаимодействия с сервисом RAS
#  Метод устанавливает значения, указанные в параметрах:
#  * ${1} - номер порта RAS
#  * ${2} - максимальное время ожидания ответа RAS
#  * ${3} - пользователь администратор кластрера
#  * ${4} - пароль пользователя администратора кластера
function make_ras_params {

    [[ -n ${1} ]] && RAS_PORTS=${1}

    [[ -n ${2} ]] && RAS_TIMEOUT=${2}

    [[ -n ${3} ]] && RAS_AUTH="--cluster-user=${3}"
    [[ -n ${4} ]] && RAS_AUTH+=" --cluster-pwd=${4}"

    export RAS_PORTS RAS_TIMEOUT RAS_AUTH

}

# Сохранить список UUID кластеров во временный файл
function push_clusters_uuid {
    CURR_CLSTR=$( timeout -s HUP "${RAS_TIMEOUT}" rac cluster list "${1%%:*}:${RAS_PORT}" 2>/dev/null | 
        awk -v FS=' +: +' '/^($|cluster|name|port)/ { if ($1){ print $2 } else {print "==="} }' |
        awk -v FS='\n' -v RS='={3}\n' -v OFS=',' -v ORS=';' '$1=$1' )

    [[ -n ${CURR_CLSTR} ]] && echo "${1%%:*}:${RAS_PORT}#${CURR_CLSTR}" | sed 's/,;/;/g'
}

# Сохранить список кластеров во временный файл
function push_clusters_list {

    if echo ${$} 2>/dev/null > "${CACHE_FILENAME}.lock"; then
        trap 'rm -f "${CACHE_FILENAME}.lock"; exit ${?}' INT TERM EXIT
        execute_tasks push_clusters_uuid "${@}" |
        if [[ -z ${IS_WINDOWS} ]]; then cat; else iconv -f CP866 -t UTF-8; fi >| "${CACHE_FILENAME}"
        rm -f "${CACHE_FILENAME}.lock"
    fi

}

# Вывести список кластеров из временных файлов:
#  - если в первом параметре указано self, то выводится только список кластеров текущего сервера
function pop_clusters_list {

    find "${TMPDIR}" -maxdepth 1 -regextype awk -regex ".*_(${RAS_PORTS//,/|})" -name "$( basename "${CLSTR_CACHE}" )_*" |
        grep -qv "^$" || error "Не найдено ни одного файла списка кластеров!"

    # ВАЖНО: Для этого блока включается extglob (возможно имеет смысл переделать)
    if [[ -n ${1} && ${1} == "self" ]]; then
        grep -i "^${HOSTNAME}" "${CLSTR_CACHE}_"?(${RAS_PORTS//,/|}) | sed -re 's/^([/][^:]+:)?//'
    else
        cat "${CLSTR_CACHE}_"?(${RAS_PORTS//,/|}) 
    fi | sed 's/ /<sp>/g; s/"//g'

}

# Вывести список кластеров в формате json:
#  - если в первом параметре указано self, то выводится только список кластеров текущего сервера
function get_clusters_list {

    pop_clusters_list "${1}" | awk -F, -v RS=";\n?" -v ORS="" 'BEGIN {print "{\"data\":[" }
        { sub(".*#",""); print (NR!=1?",":"")"{\"{#CLSTR_UUID}\":\""$1"\",\"{#CLSTR_NAME}\":\""$3"\"}" }
        END {ORS="\n"; print "]}" }' | sed 's/<sp>/ /g'

}

# Проверить актуальность файла списка кластеров
function check_clusters_cache {

    # Получим список менеджеров кластеров, в которых участвует данный сервер, следующего вида:
    #   <имя_сервера>:<номер_порта_0>[|<номер_порта_1>[|..<номер_порта_N>]]
    readarray -t RMNGR_LIST < <( if [ -z "${IS_WINDOWS}" ]; then pgrep -ax rphost; else
        wmic path win32_process where "caption like 'rphost%'" get CommandLine | grep rphost; fi |
        sed -r 's/.*-regport ([^ ]+).*/\0|\1/; s/.*-reghost ([^ ]+).*\|/\1:/' | sort -u |
        awk -F: '{ if ( clstr_list[$1]== "" ) { clstr_list[$1]=$2 } \
            else { clstr_list[$1]=clstr_list[$1]"|"$2 } } \
            END { for ( i in clstr_list ) { print i":"clstr_list[i]} }' )

    # Проверка необходимости обновления временного файла:
    #   - если временный файл не существует
    #   - если количество строк во временном файле отличается от количества элементов
    #     списка менеджеров кластеров
    #   - если временный файл старше 1 часа
    set -o noclobber
    for RAS_PORT in ${RAS_PORTS//,/ }; do
        CACHE_FILENAME="${CLSTR_CACHE}_${RAS_PORT}"
        export RAS_PORT CACHE_FILENAME
        if [[ -e ${CACHE_FILENAME} ]]; then
            if [[ ${1} == "lost" ]]; then
                cp "${CACHE_FILENAME}" "${CACHE_FILENAME}.${$}" && trap 'rm -f "${CACHE_FILENAME}.${$}"; exit ${?}' INT TERM EXIT
                for CURR_RMNGR in "${RMNGR_LIST[@]}"; do
                    CURR_LOST=$( grep "^${CURR_RMNGR%:*}" "${CACHE_FILENAME}.${$}" | \
                        sed -re "s/[^:^;]+,(${CURR_RMNGR#*:}),[^;]+;//" )
                    sed -i -re "s/^${CURR_RMNGR%:*}.*$/${CURR_LOST}/; /[^:]+:$/d" "${CACHE_FILENAME}.${$}"
                done
                grep -v "^$" "${CACHE_FILENAME}.${$}" || [[ ${#RMNGR_LIST[@]} -ne $(grep -vc "^$" "${CACHE_FILENAME}") ]] && 
                    push_clusters_list "${RMNGR_LIST[@]}"
                rm -f "${CACHE_FILENAME}.${$}" &>/dev/null   
            elif [[ ${#RMNGR_LIST[@]} -ne $(grep -vc "^$" "${CACHE_FILENAME}") ||
                $(date -r "${CACHE_FILENAME}" "+%s") -lt $(date -d "last hour" "+%s") ]]; then
                push_clusters_list "${RMNGR_LIST[@]}"
            fi
        else
            push_clusters_list "${RMNGR_LIST[@]}"
        fi
    done

}

# Доступная производительность процессов рабочих серверов
# Выводит список:
#   <имя_хоста>:<средняя_производительность>
function get_processes_perfomance {

    CLSTR_LIST=${1#*#}

    for CURR_CLSTR in ${CLSTR_LIST//;/ }; do
        timeout -s HUP "${RAS_TIMEOUT}" rac process list "--cluster=${CURR_CLSTR%%,*}" \
            ${RAS_AUTH} "${1%#*}" 2>/dev/null | \
            awk '/^(host|available-perfomance|$)/' | perl -pe "s/.*: ([^.]+).*\n/\1:/" | \
            awk -F: '{ apc[$1]+=1; aps[$1]+=$2 } END { for (i in apc) { print i":"aps[i]/apc[i] } }'
    done

}

# Получить каталоги серверов 1С
function get_server_directory {
    if [ -z "${IS_WINDOWS}" ]; then
        pgrep -a ragent | sed -r 's/.*-d ([^ ]+).*/\1/'
    else
        wmic path win32_process where "caption like 'ragent.exe'" get commandline /format:csv | \
            awk -F, '/ragent/ { print $2 }' | sed -re 's/.*-d "([^"]+).*/\1/; s/^/\//; s/\\/\//g; s/://'
    fi | sed -re 's/(.*)[/]$/\1/' | sort -u | grep -v "^$"
    #TODO: Возможно имеет смысл задавать значение SRV1CV8_DATA в случае если его не удалось определить из строки запуска
    # т.е. в списке значений будет пресутствовать пустая строка
    # - для Linux, пустую строку можно заменить значением полученным в результате работы похжей команды
    #   $(awk -v uid="^$(awk '/Uid/ {print $2}' /proc/"$(pgrep ragent)"/status 2>/dev/null)$" -F: \
    #     '$3 ~ uid {print $6}' /etc/passwd)/.1cv8/1C/1cv8"
    #   ВАЖНО: однако следует учитывать имено pid процесса ragent-а у которого не указан каталог сервера!
    # - для Windows, остуствие указанного каталога сервера возможно толькопри ручном запуске ragent
}

# Cписок информационных баз в виде json + файл кэша (идентификаторы: кластер, информационная база)
# Список кластеров берется из файла кэша кластеров 1c_clusters_cache
#  - если в первом параметре указано self, то выводится только список информационных баз текущего сервера
function get_infobases_list {

    cat /dev/null > "${IB_CACHE}"

    readarray -t SERVERS_LIST < <( pop_clusters_list "${1}" )
    BASE_INFO='{"data":[ '
    MAX_THREADS=0
    BASE_INFO+="$( execute_tasks get_clusters_infobases "${SERVERS_LIST[@]}" )"
    echo "${BASE_INFO%, } ]}" | sed 's/<sp>/ /g'
}

# Список информационных баз кластеров, указанного в ${1} сервера 1С, в формате json
# В параметр ${1} передается строка вида:
#   [<имя_сервера>:]<идентификатор_кластера>,<порт_rmngr>,<имя_кластера>;[<идентификатор_кластера>,<порт_rmngr>,<имя_кластера>;[...]]
# где
#  <имя_сервера> - необязательный параметр, указывает адрес сервера 1С (не указывается, если требуется получить список с текущего сервера)
#  <идентификатор_кластера> - идентификатор (UUID) кластера
#  <порт_rmngr> - порт на котором работает процесс rmngr данного кластера
#  <имя_кластера> - имя кластера
# комбинация <идентификатор_кластера>,<порт_rmngr>,<имя_кластера>; может встречаться в строке столько раз, 
#  сколько имеется кластеров на указанном (<имя_сервера>) сервере 1С Предприятия
function get_clusters_infobases {
    
    RMNGR_HOST=${1%%#*}
    CLUSTERS_LIST=${1#*#}

    for CURRENT_CLUSTER in ${CLUSTERS_LIST//;/ }; do
        readarray -t BASE_LIST < <( timeout -s HUP "${RAS_TIMEOUT}" rac infobase summary list \
            --cluster "${CURRENT_CLUSTER%%,*}" ${RAS_AUTH} "${RMNGR_HOST}" 2>/dev/null |
            if [[ -z ${IS_WINDOWS} ]]; then cat; else iconv -f CP866 -t UTF-8; fi |
            awk -v FS=' +: +' '/^(infobase|name|)(\s|$)/ { if ( $2 ) { print $2 } else { print "===" } }' | 
                awk -v FS='\n' -v RS='={3}\n' -v OFS='|' '$1=$1' | sed 's/|$//' )
        for CURRENT_BASE in "${BASE_LIST[@]}"; do
            echo "{ \"{#CLSTR_UUID}\":\"${CURRENT_CLUSTER%%,*}\",\"{#CLSTR_NAME}\":\"${CURRENT_CLUSTER##*,}\",\"{#IB_UUID}\":\"${CURRENT_BASE%%|*}\",\"{#IB_NAME}\":\"${CURRENT_BASE#*|}\" }, "
            echo "${CURRENT_CLUSTER%%,*} ${CURRENT_BASE%%|*}" >> "${IB_CACHE}"
        done
    done
}

# Список сеансов кластера, указанного в параметрах:
#   - ${1} - имя сервера 1С
#   - ${2} - UUID кластера
#   - ${3} - необязательный, если принимает значение "license", то выводится информация
#       только о сеансах, потребляющих клиентскую лицензию
function get_sessions_list {

    SERVER_NAME=${1}
    CLUSTER_UUID=${2}

    SESSION_FORMAT="session:session-id:infobase:user-name:app-id:hibernate:duration-current:data-separation"
    LICENSE_FORMAT="session:full-name:rmngr-address"

    timeout -s HUP "${RAS_TIMEOUT}" rac session list --cluster="${CLUSTER_UUID}" \
        ${RAS_AUTH} "${SERVER_NAME}" 2>/dev/null | if [[ -z ${IS_WINDOWS} ]]; then cat; else iconv -f CP866 -t UTF-8; fi |
        awk -v FS=' +: +' -v format=${SESSION_FORMAT} \
        'BEGIN { print "FMT#"format"\n" } ( $0 ~ "^("gensub(":","|","g",format)"|)($| )" ) { if ( $1 == "app-id" ) {
            switch ($2) {
                case "WebClient": print "wc"; break;
                case /1CV8/: print "cl"; break;
                case "BackgroundJob": print "bg"; break;
                case "WSConnection": print "ws"; break;
                case "HTTPServiceConnection": print "hs"; break; 
                default: print $2; }
        } else { if ($1 == "user-name" && $2 == "" ) { print "empty" } else { print $2; } } }' |
        awk -F':' -v RS='' -v OFS=':' '$1=$1' | ( if [[ ${3} != "license" ]]; then cat; else
            awk -F':' -v OFS=":" -v format="${LICENSE_FORMAT#*:}" 'FNR==NR{licenses[$1]=gensub("^[^:]+(:|$)","","g",$0); next} 
                ($1 in licenses || $0 ~ "^FMT#") { if ( $0 ~ "^FMT#" ) { print $0,format } else { print $0,licenses[$1] } }' \
            <( timeout -s HUP "${RAS_TIMEOUT}" rac session list --licenses --cluster="${CLUSTER_UUID}" \
                ${RAS_AUTH} "${SERVER_NAME}" 2>/dev/null |
                awk -v FS=' +: +' -v format="${LICENSE_FORMAT}" '( $0 ~ "^("gensub(":","|","g",format)"|)($| )" ) { 
                    if ( $1 == "full-name" ) { value=gensub("[^\"].*/", "", "g", $2) } else { value=$2 }; print value||(!$1)?value:"n/a" }' |
                awk -v RS='' -v OFS=':' '$1=$1' ) - ; fi )

}

export -f get_sessions_list
