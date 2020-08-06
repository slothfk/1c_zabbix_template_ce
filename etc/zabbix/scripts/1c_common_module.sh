#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (общие переменные и функции)
#
# (c) 2019-2020, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

# Имя сервера, используемое в кластере 1С Предприятия
HOSTNAME=$(hostname -s)

# Добавление пути к бинарным файлам 1С Предприятия
PATH=${PATH}:$(ls -d /opt/1C/v8*/[xi]* | tail -n1)

# Модуль менеджера задач
TM_MODULE="1c_common_tm.sh"
[[ -f ${0%/*}/${TM_MODULE} ]] && source ${0%/*}/${TM_MODULE} 2>/dev/null && TM_AVAILABLE=1

# Каталог для различных кешей скриптов
CACHE_DIR="/var/tmp/1C"
[[ ! -d ${CACHE_DIR} ]] && mkdir -p ${CACHE_DIR}

# Файл списка кластеров
CLSTR_CACHE="${CACHE_DIR}/1c_clusters_cache"

# Параметры взаимодействия с сервисом RAS
declare -A RAS_PARAMS=([port]=1545 [timeout]=1.5 [auth]="")

# Общие для всех скрпитов тексты ошибок
ERROR_UNKNOWN_MODE="Неизвестный режим работы скрипта!"
ERROR_UNKNOWN_PARAM="Неизвестный параметр для данного режима работы скрипта!"

# Вывести сообщение об ошибке переданное в аргументе и выйти с кодом 1
function error {
    echo "ОШИБКА: ${1}" >&2
    exit 1
}

# Вывести разделительную строку длинной ${1} из символов ${2}
# По-умолчанию раделительная строка - это 80 символов "-"
function put_brack_line {
    [[ -n ${1} ]] && LIMIT=${1} || LIMIT=80
    [[ -n ${2} ]] && CHAR=${2} || CHAR="-"

    printf "%*s\n" ${LIMIT} ${CHAR} | sed "s/ /${CHAR}/g"
}

# Выполнить серию команд ${1} с параметром, являющимся элементом массива ${@}, следующим за ${1}
function execute_tasks {
    TASK_CMD=${1}
    shift

    if [[ -z ${TM_AVAILABLE} || ${#@} -eq 1 ]]; then
        for CURR_TASK in ${@}; do
            ${TASK_CMD} ${CURR_TASK}
        done
    else
        TASKS_LIST=(${@})
        tasks_manager ${TASK_CMD} 3
    fi
}

# Проверить наличие ring license и вернуть путь до ring
function check_ring_license {
    [[ ! -f /etc/1C/1CE/ring-commands.cfg ]] &&  error "Не установлена утилита ring!"
    LIC_TOOL=$(grep license-tools /etc/1C/1CE/ring-commands.cfg | cut -d: -f2)

    [[ -z ${LIC_TOOL} ]] && error "Не установлена утилита license-tools!"

    ls ${LIC_TOOL%\/*\/*}/*ring*/ring
}

# Получить список имен установленных программных лицензий
# в качестве параметра ${1} указать путь до ring
function get_license_list {
    ${1} license list --send-statistics false | sed -re 's/^([0-9\-]+).*/\1/'
}

# Установить параметры взаимодействия с сервисом RAS
#  Метод заменяет значения в массиве RAS_PARAMS значениями,
#  указанными в параметрах:
#  * ${1} - номер порта RAS
#  * ${2} - максимальное время ожидания ответа RAS
#  * ${3} - пользователь администратор кластрера
#  * ${4} - пароль пользователя администратора кластера
function make_ras_params {

    [[ -n ${1} ]] && RAS_PARAMS[port]=${1}

    [[ -n ${2} ]] && RAS_PARAMS[timeout]=${2}

    [[ -n ${3} ]] && RAS_PARAMS[auth]="--cluster-user=${3}"

    [[ -n ${4} ]] && RAS_PARAMS[auth]+=" --cluster-pwd=${4}"

}

# Сохранить список кластеров во временный файл
function push_clusters_list {

    # Сохранить список UUID кластеров во временный файл
    function push_clusters_uuid {
        CURR_CLSTR=$( timeout -s HUP ${RAS_PARAMS[timeout]} rac cluster list \
            ${1%%:*}:${RAS_PARAMS[port]} | grep -Pe '^(cluster|name|port)' | \
            perl -pe 's/[ "]//g; s/^name:(.*)$/\1\n/; s/^cluster:(.*)/\1,/; s/^port:(.*)/\1,/; s/\n//' | \
            grep -Pe ${1##*:} | perl -pe 's/(.*,)\d+,(.*)/\1\2/; s/\n/;/' )

        [[ -n ${CURR_CLSTR} ]] && echo ${1%%:*}:${CURR_CLSTR} >> ${CLSTR_CACHE}
    }

    # Получим список менеджеров кластеров, в которых участвует данный сервер, следующего вида:
    #   <имя_сервера>:<номер_порта_0>[|<номер_порта_1>[|..<номер_порта_N>]]
    RMNGR_LIST=( $(pgrep -ax rphost | \
        sed -r 's/.*-regport ([^ ]+).*/\0|\1/; s/.*-reghost ([^ ]+).*\|/\1:/' | sort -u | \
        awk -F: '{ if ( clstr_list[$1]== "" ) { clstr_list[$1]=$2 } \
            else { clstr_list[$1]=clstr_list[$1]"|"$2 } } \
            END { for ( i in clstr_list ) { print i":"clstr_list[i]} }' ) )

    # Проверка необходимости обновления временного файла:
    #   - если временный файл не сущствует
    #   - если количество строк во временном файле отличается от количества элементов
    #     списка менеджеров кластеров
    #   - если временный файл старше 1 часа
    if [[ ! -e ${CLSTR_CACHE} || ${#RMNGR_LIST[@]} -ne $(grep -c "." ${CLSTR_CACHE}) ||
        $(date -r ${CLSTR_CACHE} "+%s") -lt $(date -d "last hour" "+%s") ]]; then

        cat /dev/null > ${CLSTR_CACHE}

        execute_tasks push_clusters_uuid ${RMNGR_LIST[@]}
    fi

}

# Считать список кластеров из временного файла в массив HOSTS_LIST
#   (массив должен быть инициализирован до вызова метода)
function pop_clusters_list {

    push_clusters_list # Обновить список перед извлечением

    if [[ -n ${1} && ${1} == "self" ]]; then
        HOSTS_LIST+=($(grep -i "^${HOSTNAME}" ${CLSTR_CACHE}));
    else
        while read -r CURRENT_HOST; do
            HOSTS_LIST+=(${CURRENT_HOST})
        done < ${CLSTR_CACHE}
    fi

}
