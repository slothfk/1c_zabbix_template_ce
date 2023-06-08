#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (центральный сервер)
#
# (c) 2020-2023, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

WORK_DIR=$(dirname "${0}" | sed -r 's/\\/\//g; s/^(.{1}):/\/\1/')

# Включить опцию extglob если отключена (используется в 1c_common_module.sh)
shopt -q extglob || shopt -s extglob

source "${WORK_DIR}/1c_common_module.sh" 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

function get_clusters_sessions {

    CLSTR_LIST=${1##*#}

    for CURR_CLSTR in ${CLSTR_LIST//;/ }; do
        get_sessions_list "${1%#*}" "${CURR_CLSTR%%,*}" | ( if [[ -s ${IB_CACHE} ]]; then
            awk -v cluster="CL#${CURR_CLSTR%%,*}" -v OFS=':' -F':' \
            'FNR==NR{ if ( $0 ~ "^"substr(cluster,4) ) { split($0, ib_uuid, " "); ss["IB#"ib_uuid[2]]=0; }; next }
            BEGIN { ss[cluster]=0; } { 
                if ( $0 ~ "^FMT#") { 
                    split($0,a,"#|:"); for (i in a) { f[a[i]]=i-1 } 
                } else if ( length(f) > 0 ) {
                    if ( $f["app-id"] ~ /(cl|wc)/ ) { app_id="cl" } else { app_id = $f["app-id"] }
                    ib_mark="IB#"$f["infobase"];
                    ss[cluster]++; ss[ib_mark]++;
                    if ( app_id != "cl" ) { sc[app_id,cluster]++; sc[app_id,ib_mark]++ }
                    if ( $f["hibernate"] == "yes" ) { sc["hb",cluster]++; sc["hb",ib_mark]++ }
                    if ( $f["duration-current"] != 0) {
                        as[cluster]++; as[ib_mark]++;
                        if ( asd[app_id,cluster] < $f["duration-current"] ) {
                            asd[app_id,cluster]=$f["duration-current"]; asd[app_id,ib_mark]=$f["duration-current"];
			                if ( app_id == "cl" ) { asu[cluster]=$f["user-name"]" ("$f["session-id"]")"; asu[ib_mark]=$f["user-name"]" ("$f["session-id"]")" }
                        } else if ( asd[app_id,ib_mark] < $f["duration-current"] ) { asd[app_id,ib_mark]=$f["duration-current"];
			                if ( app_id == "cl" ) { asu[ib_mark]=$f["user-name"]" ("$f["session-id"]")"; }
	                    }
                    } 
                } 
            } END { for (i in ss) {
                    print i,ss[i]?ss[i]:0,sc["bg",i]?sc["bg",i]:0,sc["hb",i]?sc["hb",i]:0,
                        sc["ws",i]?sc["ws",i]:0,sc["hs",i]?sc["hs",i]:0,as[i]?as[i]:0,
                        asd["cl",i]?asd["cl",i]:0,asd["bg",i]?asd["bg",i]:0,
                        asd["ws",i]?asd["ws",i]:0,asd["hs",i]?asd["hs",i]:0,asu[i] } }' "${IB_CACHE}" -
        else
            awk -v cluster="CL#${CURR_CLSTR%%,*}" -v OFS=':' -F':' \
            'BEGIN { ss[cluster]=0; } { 
                if ( $0 ~ "^FMT#") { 
                    split($0,a,"#|:"); for (i in a) { f[a[i]]=i-1 } 
                } else if ( length(f) > 0 ) {
                    if ( $f["app-id"] ~ /(cl|wc)/ ) { app_id="cl" } else { app_id = $f["app-id"] }
                    ss[cluster]++;
                    if ( app_id != "cl" ) { sc[app_id,cluster]++ }
                    if ( $f["hibernate"] == "yes" ) { sc["hb",cluster]++ }
                    if ( $f["duration-current"] != 0) {
                        as[cluster]++;
                        if ( asd[app_id,cluster] < $f["duration-current"] ) {
                            asd[app_id,cluster]=$f["duration-current"];
			                if ( app_id == "cl" ) { asu[cluster]=$f["user-name"]" ("$f["session-id"]")"; }
	                    }
                    } 
                } 
            } END { for (i in ss) {
                    print i,ss[i]?ss[i]:0,sc["bg",i]?sc["bg",i]:0,sc["hb",i]?sc["hb",i]:0,
                        sc["ws",i]?sc["ws",i]:0,sc["hs",i]?sc["hs",i]:0,as[i]?as[i]:0,
                        asd["cl",i]?asd["cl",i]:0,asd["bg",i]?asd["bg",i]:0,
                        asd["ws",i]?asd["ws",i]:0,asd["hs",i]?asd["hs",i]:0,asu[i] } }'
        fi )
    done

}

function get_session_amounts {

    check_clusters_cache

    ( execute_tasks get_clusters_sessions $( pop_clusters_list self ) ) | \
        awk -F: -v OFS=':' '{ print $0; 
            if ($1 !~ /^IB/) { sc["all"]+=$2; sc["bg"]+=$3; sc["hb"]+=$4; sc["ws"]+=$5; sc["hs"]+=$6; sc["as"]+=$7;
                if ( asd["cl"] < $8 ) { asd["cl"]=$8; } 
                if ( asd["bg"] < $9 ) { asd["bg"]=$9; } 
                if ( asd["ws"] < $10 ) { asd["ws"]=$10; } 
                if ( asd["hs"] < $11 ) { asd["hs"]=$11; } 
            } } 
            END { print "summary",sc["all"]?sc["all"]:0,sc["bg"]?sc["bg"]:0,sc["hb"]?sc["hb"]:0,\
                sc["ws"]?sc["ws"]:0,sc["hs"]?sc["hs"]:0,sc["as"]?sc["as"]:0,asd["cl"]?asd["cl"]:0,\
                asd["bg"]?asd["bg"]:0,asd["ws"]?asd["ws"]:0,asd["hs"]?asd["hs"]:0 }' | sed 's/<sp>/ /g'

}

function get_infobases_restrictions {
    if [[ -z ${IS_WINDOWS} ]]; then
        COMMAND_PREFIX=( sudo -u "${USR1CV8}" )
    else 
        COMMAND_PREFIX=()
    fi
    get_server_directory | xargs -I server_directory "${COMMAND_PREFIX[@]}" find server_directory -maxdepth 2 -name 1CV8Clst.lst -exec grep DBMS -A1 {} + |
        perl -pe 's/([^}],)\r?\n/\1/' |
        perl -pe 's/.*{(\w{8}-\w{4}-\w{4}-\w{4}-\w{12}),.+{([01]),([0-9]+),([0-9]+),.+},([01]),.*/IB#\1,\2,\3,\4,\5/' | 
        awk -v current_date="$(date +%Y%m%d%H%M%S)" -F, '{ if ( $2 == "1" && $3 < current_date && $4 > current_date ) { sl=1 } else { sl=0 }; print $1","sl","$5}'
}

case ${1} in
    sessions) shift; make_ras_params "${@}"; get_session_amounts ;;
    infobases) shift 2; make_ras_params "${@}"; get_infobases_list self;;
    clusters) shift; make_ras_params "${@}"; get_clusters_list self ;;
    ib_restrict) get_infobases_restrictions ;;
    *) error "${ERROR_UNKNOWN_MODE}" ;;
esac
