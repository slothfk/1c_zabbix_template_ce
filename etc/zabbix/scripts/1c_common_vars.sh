# Добавление пути к бинарным файлам 1С Предприятия
PATH=${PATH}:$(ls -d /opt/1C/v8*/[xi]* | tail -n1)

# Модуль менеджера задач
TM_MODULE="1c_common_tm.sh"
[[ -f ${0%/*}/${TM_MODULE} ]] && source ${0%/*}/${TM_MODULE} 2>/dev/null && TM_AVAILABLE=1

function execute_tasks {

    TASK_CMD=${1}
    shift

    if [[ -z ${TM_AVAILABLE} || ${#@} -eq 1 ]]; then
        for CURR_TASK in ${@}
        do
            ${TASK_CMD} ${CURR_TASK}
        done
    else
        TASKS_LIST=(${@})
        tasks_manager ${TASK_CMD} 0
    fi

}

# Каталог для различных кешей скриптов
CACHE_DIR="/var/tmp/1C"

# Порт RAS по умолчанию
RAS_PORT=1545
# Максимальное время ожидания ответа от RAS
RAS_TIMEOUT=1.5