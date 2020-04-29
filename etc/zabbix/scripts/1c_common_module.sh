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

# Порт RAS по умолчанию
RAS_PORT=1545
# Максимальное время ожидания ответа от RAS
RAS_TIMEOUT=1.5

# Вывести сообщение об ошибке переданное в аргументе и выйти с кодом 1
function error {
    echo "ОШИБКА: "${@} >&2
    exit 1
}

# Вывести разделительную строку длинной ${1} из символов ${2}
# По-умолчанию раделительная строка - это 80 символов "-"
function put_brack_line {
    [[ -n ${1} ]] && LIMIT=${1} || LIMIT=80
    [[ -n ${2} ]] && CHAR=${2} || CHAR="-"

    printf "%.${LIMIT}d\n" 0 | sed "s/0/${CHAR}/g"
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
    ${1} license list --send-statistics false | cut -d' ' -f1
}
