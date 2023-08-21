#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (сервер лицензирования)
#
# (c) 2019-2023, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

WORK_DIR=$(dirname "${0}" | sed -r 's/\\/\//g; s/^(.{1}):/\/\1/')

# Включить опцию extglob если отключена (используется в 1c_common_module.sh)
shopt -q extglob || shopt -s extglob

source "${WORK_DIR}/1c_common_module.sh" 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

function get_license_counts {

    CLSTR_LIST=${1##*#}

    for CURR_CLSTR in ${CLSTR_LIST//;/ }; do
        # Выводим первую строку (строка формата), после чего формируем список уникальных сеансов для испключения
        #   повторного учета выданной лицензии в случае УО > 1 (см. #86)
        ( { read -r ; echo "$REPLY" ; sort -u; } < <( get_sessions_list "${1%#*}" "${CURR_CLSTR%%,*}" license ) ) | 
        if [[ -s ${IB_CACHE} ]]; then
            awk -F':' -v OFS=':' -v hostname="${HOSTNAME,,}" -v cluster="CL#${CURR_CLSTR%%,*}" \
                'FNR==NR{ if ($0 ~ "^"substr(cluster,4)) { split($0, ib_uuid, " "); sc["IB#"ib_uuid[2]]=0 }; next}
                BEGIN { sc[cluster]=0 } {
                    print;
                    if ( $0 ~ "^FMT#") { 
                        split($0,a,"#|:"); for (i in a) { f[a[i]]=i-1 } 
                    } else if ( length(f) > 0 ) {
                        ib_mark="IB#"$f["infobase"];
                        sc[cluster]++; sc[ib_mark]++; uc[cluster][$f["user-name"]]; uc[ib_mark][$f["user-name"]];
                        if ( index(tolower($f["rmngr-address"]), hostname) > 0 ) { hc[cluster]++; hc[ib_mark]++; }
                        if ($f["app-id"] == "wc") { wc[cluster]++; wc[ib_mark]++; }
                        if ($f["rmngr-address"] == "n/a") { cc[cluster]++; cc[ib_mark]++; }
                    }
                } END { 
                    for (i in sc) { 
                        print i,hc[i]?hc[i]:0,length(uc[i]),sc[i]?sc[i]:0,cc[i]?cc[i]:0,wc[i]?wc[i]:0 
                    } 
                }' "${IB_CACHE}" -
        else
            awk -F':' -v OFS=':' -v hostname="${HOSTNAME,,}" -v cluster="CL#${CURR_CLSTR%%,*}" \
                'BEGIN { sc[cluster]=0 } {
                    print;
                    if ( $0 ~ "^FMT#") { 
                        split($0,a,"#|:"); for (i in a) { f[a[i]]=i-1 } 
                    } else if ( length(f) > 0 ) {
                        sc[cluster]++; uc[cluster][$f["user-name"]];
                        if ( index(tolower($f["rmngr-address"]), hostname) > 0 ) { hc[cluster]++ }
                        if ($f["app-id"] == "wc") { wc[cluster]++ }
                        if ($f["rmngr-address"] == "n/a") { cc[cluster]++ }
                    }
                } END { 
                    for (i in sc) { 
                        print i,hc[i]?hc[i]:0,length(uc[i]),sc[i]?sc[i]:0,cc[i]?cc[i]:0,wc[i]?wc[i]:0 
                    } 
                }'
        fi
    done

}

function used_license {

    export MAX_THREADS=0 # Отключаем ограничение по количеству параллельно выполняемых задач
    check_clusters_cache
    readarray LIC_LIST < <( find /var/1C/licenses "${ALLUSERSPROFILE}/Application\ Data/1C/licenses" "${ALLUSERSPROFILE}/1C/licenses" \
        -maxdepth 1 -name "*.lic" -exec basename {} \; 2>/dev/null )

    ( execute_tasks get_license_counts $( pop_clusters_list ) ) | \
        awk -F: -v OFS=':' -v hostname="${HOSTNAME,,}" -v lic_list="${LIC_LIST[*]}" '{
            switch ($0) {
                case /^FMT#/: split($0,a,"#|:"); for (i in a) { f[a[i]]=i-1 }; break
                case /^(IB|CL)#/: print; break
                default:
                    sc++; uc[$f["user-name"]]; 
                    if ( index(tolower($f["rmngr-address"]), hostname) > 0 ) { 
                        hc++;
                        lic[gensub("\"","","g",$f["full-name"])]++;
                    }
                    if ($f["app-id"] == "wc") { wc++ }
                    if ($f["rmngr-address"] == "n/a") { cc++ }
            }
        } END {
            split(lic_list, lic_files, " ");
            for ( i in lic_files ) {
                print "LIC#"lic_files[i],lic[lic_files[i]]?lic[lic_files[i]]:0
            }
            print "summary",hc?hc:0,length(uc),sc?sc:0,cc?cc:0,wc?wc:0
        }'

}

# Проверяет наличие процессов сервера 1С для кластера по указанным параметрам:
#  - ${1} - должен принимать заничение rmngr или rphost
#  - ${2} - UUID кластера, к которому подключен сервер лицензирования
function check_cluster_process {

    RAC_PARAM=$(echo "${1}" | sed 's/rmngr/manager/; s/rphost/process/')
    PROCESS_UUID=$(timeout -s HUP "${RAS_TIMEOUT}" rac "${RAC_PARAM}" list  --cluster "${2}"  ${RAS_AUTH} \
        "$( awk -F# -v cluster="${2}" '$0 ~ cluster { print $1 }' "${CLSTR_CACHE}_"?(${RAS_PORTS//,/|}) )" 2>/dev/null | 
        awk -v FS=" +: *" -v filter="${RAC_PARAM}" '( $0 ~ "^("filter"|host|)( |$)" ) { print $2}' | 
        awk -v RS='' -v OFS=':' '$1=$1' | awk -F":" -v hostname="${HOSTNAME,,}" '( tolower($0) ~ ":"hostname ) { print $1 }')
    if [[ -z ${PROCESS_UUID} ]]; then
        echo 0
    else
        if [[ -z ${IS_WINDOWS} ]]; then
            pgrep "${1}" -a
        else 
            wmic path win32_process where "caption like '${1}.exe'" get commandline /format:csv
        fi | awk "/${PROCESS_UUID//$'\n'/|}|${2}/ { count++ } END { print count?count:0 }"
    fi

}

case ${1} in
    process) CLSTR_UUID=${2}; CHECK_MODE=${3} ; shift 2 ;;&
    used|infobases|clusters|process) shift; make_ras_params "${@}" ;;&
    used) used_license ;;
    infobases) get_infobases_list;;
    clusters) get_clusters_list ;;
    process) check_cluster_process "${CHECK_MODE}" "${CLSTR_UUID}" ;;
    *) error "${ERROR_UNKNOWN_MODE}" ;;
esac
