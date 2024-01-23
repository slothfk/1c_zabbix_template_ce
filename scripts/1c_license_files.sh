#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (файлы программных лицензий)
#
# (c) 2023, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

WORK_DIR=$(dirname "${0}" | sed -r 's/\\/\//g; s/^(.{1}):/\/\1/')

# Включить опцию extglob если отключена (используется в 1c_common_module.sh)
shopt -q extglob || shopt -s extglob

source "${WORK_DIR}/1c_common_module.sh" 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

# Проверяет соответствие оборудования на компьютере оборудованию, 
#  которое было зафиксировано в момент активации лицензии
#  - в качестве превого параметра указывается путь до утилиты ring
#  - в качестве второго параметра указывается имя лицензии
function license_check {
    [[ -z "${1}" ]] && error "${ERROR_UNKNOWN_PARAM}"

    RESULT=$("${1}" license validate --name "${2}" --send-statistics false 2>/dev/null) && echo "Ok" || echo "${RESULT}"
}

# Возвращает сводную информацию по файлам лицензий
# ВАЖНО: Не использует для этих целей утилиту ring, поскольку:
#  - утилита ring имеет длительный отклик и высокую нагрузку на ЦПУ при большом количестве файлов лицензий
#  - утилита ring не выводит информацию о сроке действия лицензии для срочных лицензий (актуально для версии 0.15.0-2)
# ВАЖНО: Анализируется информация, содержащаяся в файле лицензии, что было не всегда, поэтому в случае
#  файла "старого формата" функция может возвращать "пустой результат"
function get_licenses_info {
    ( find /var/1C/licenses/ "${ALLUSERSPROFILE}/Application\ Data/1C/licenses" "${ALLUSERSPROFILE}/1C/licenses" -maxdepth 1 -name "*.lic" \
        -exec awk '/^(Номер продукта|Product code|Срок действия|Valid till)/ {
            str[FILENAME]=str[FILENAME]?str[FILENAME]":"gensub("^[^:]+[:] *","","g",$0):FILENAME":"gensub("^[^:]+[:] *","","g",$0)
        } END { for (i in str) { print str[i] }}' {} \; 2>/dev/null ) | sed -re 's/\r//g' |
    xargs -I license_file basename license_file | 
    sed -re 's/(0{7}10{3}1)5/\10/;
        s/(0{7}[10]0)10{3}/\10500/;
        s/:[0-9]{9}0*/:/;
        s/^([^:]+[:][^:]*[:])([0-9]{2})[.]([0-9]{2})[.]([0-9]{4}).*/\1\4\3\2/' | 
    awk -F: -v OFS=':' '{ if ($2) { client+=$2 } else {server++ }; print $1,$2?$2:"s",gensub("^[^:]+:[^:]*:","","g",$0)
        } END { print "summary",server?server:0,client?client:0 }'
}

# Возвращает список файлов программных лицензий в формате json
#  - в качестве первого параметра указывается путь до утилиты ring
function get_license_list {
    [[ -z ${1} ]] && error "${ERROR_UNKNOWN_PARAM}"
    
    "${1}" license list --send-statistics false 2>/dev/null | 
        sed -re 's/([0-9]+)[-]([0-9]+)[^"]+"([0-9]+[.]lic)".*/\1 \2 \3/' | 
        awk -F' ' -v ORS='' 'BEGIN { print "{\"data\":[" } 
            { print (NR!=1?",":"")"{ \"{#NUMBER}\":\""$2"\",\"{#PIN}\":\""$1"\",\"{#FILE}\":\""$3"\" }" } 
        END { print "]}" }'
}

case ${1} in
    check) license_check "$(check_ring_license)" "${2}";;
    info) get_licenses_info ;;
    list) get_license_list "$(check_ring_license)" ;;
    *) error "${ERROR_UNKNOWN_MODE}" ;;
esac
