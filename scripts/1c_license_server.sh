#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (сервер лицензирования)
#
# (c) 2019-2020, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

WORK_DIR=$(dirname "${0}" | sed -r 's/\\/\//g; s/^(.{1}):/\/\1/')
source "${WORK_DIR}/1c_common_module.sh" 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

function licenses_summary {

    RING_TOOL=$(check_ring_license) && export RING_TOOL || exit 1
        
    ( execute_tasks license_info $(get_license_list "${RING_TOOL}") ) | \
        awk 'BEGIN { files=0; users=0 } 
            { files+=1; users+=$1 } 
            END { print files":"users }'

}

function license_info {

    CURRENT_CODE=$( "${RING_TOOL}" license info --send-statistics false --name "${1}" | \
        sed -re 's/(0{7}10{3}1)5/\10/; s/(0{7}[10]0)10{3}/\10500/' | \
        awk -F':' '/0{7}[10]0(0{3}[35]|00[125]0|0[135]00)/ { print $2; exit}' )

    [[ -n ${CURRENT_CODE} ]] && echo "${CURRENT_CODE:10}"

}

function get_license_counts {

    CLSTR_LIST=${1##*:}

    for CURR_CLSTR in ${CLSTR_LIST//;/ }; do
        timeout -s HUP "${RAS_TIMEOUT}" rac session list --licenses --cluster="${CURR_CLSTR%%,*}" \
            ${RAS_AUTH} "${1%%:*}:${RAS_PORT}" 2>/dev/null | \
            awk '/^(session|user-name|app-id|rmngr-address|)(\s|$)/ { print $3}' | awk -v RS='' -v OFS='|' '$1=$1' | sort -u | \
        awk -F'|' -v OFS="|" 'FNR==NR{sess_id[$1]=$2; next} ($1 in sess_id) {print sess_id[$1],$2,$3,$4 }' \
        <( timeout -s HUP "${RAS_TIMEOUT}" rac session list --cluster="${CURR_CLSTR%%,*}" \
            ${RAS_AUTH} "${1%%:*}:${RAS_PORT}" 2>/dev/null | \
            awk '/^(session|infobase|)(\s|$)/ { print $3}' | awk -v RS='' -v OFS="|" '$1=$1' ) - | \
            awk -F'|' -v OFS=':' -v hostname="${HOSTNAME,,}" -v cluster="CL#${CURR_CLSTR%%,*}" \
                'FNR==NR{ if ($0 ~ "^"substr(cluster,4)) { split($0, ib_uuid, " "); sc["IB#"ib_uuid[2]]=0 }; next} \
                BEGIN { sc[cluster]=0 }
                { ib_mark="IB#"$1; if ($2 != "") { sc[cluster]+=1; sc[ib_mark]+=1; uc[cluster][$2]; uc[ib_mark][$2]; \
                if ( index(tolower($4), hostname) > 0 ) { hc[cluster]+=1; hc[ib_mark]+=1; } \
                if ($3 == "WebClient") { wc[cluster]+=1; wc[ib_mark]+=1; } \
                if ($4 == "") { cc[cluster]+=1; cc[ib_mark]+=1; } } } \
                END {for (i in sc) { print i,(hc[i]?hc[i]:0),(length(uc[i])),(sc[i]?sc[i]:0),(cc[i]?cc[i]:0),(wc[i]?wc[i]:0) } }' "${IB_CACHE}" -
    done

}

function used_license {

    MAX_THREADS=0 # Отключаем ограничение по количеству параллельно выполняемых задач
    check_clusters_cache

    ( execute_tasks get_license_counts $( pop_clusters_list ) ) | \
        awk -F: -v OFS=':' '{ print $0; if ($1 !~ /^IB/) { ul+=$2; uu+=$3; as+=$4; cl+=$5; wc+=$6; } } \
            END { print "summary",ul?ul:0,uu?uu:0,as?as:0,cl?cl:0,wc?wc:0 }' | sed 's/<sp>/ /g'

}

function check_clusters_disconnection {

    LOST_CLSTR=$( check_clusters_cache lost | sed 's/ /<sp>/g; s/"//g' )
    
    if [[ -n ${LOST_CLSTR} ]]; then
        echo "Произошло отключение от кластера (сервер, имя):"
        for CURR_RMNGR in ${LOST_CLSTR}; do
            for CURR_CLSTR in ${CURR_RMNGR//;/ }; do
                echo "${CURR_RMNGR%:*} - ${CURR_CLSTR##*,}" | sed 's/<sp>/ /g'
            done
        done
    else
        echo "OK"
    fi

}

case ${1} in
    info) licenses_summary ;;
    used) shift; make_ras_params "${@}"; used_license ;;
    infobases) shift; make_ras_params "${@}"; get_infobases_list;;
    clusters) get_clusters_list ;;
    check) check_clusters_disconnection ;;
    *) error "${ERROR_UNKNOWN_MODE}" ;;
esac
