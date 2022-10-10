#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (центральный сервер)
#
# (c) 2020, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

WORK_DIR=$(dirname "${0}" | sed -r 's/\\/\//g; s/^(.{1}):/\/\1/')
source "${WORK_DIR}/1c_common_module.sh" 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

function get_clusters_list {

    pop_clusters_list self | perl -pe 's/;[^\n]/\n/; s/;//' | \
        awk 'BEGIN {FS=","; print "{\"data\":[" } \
            {print "{\"{#CLSTR_UUID}\":\""$1"\",\"{#CLSTR_NAME}\":\""$3"\"}," } \
            END { print "]}" }' | \
        perl -pe 's/\n//;' | perl -pe 's/(.*),]}/\1]}\n/; s/<sp>/ /g'

}

function get_clusters_sessions {

    for CURR_CLSTR in ${1//;/ }; do
        timeout -s HUP "${RAS_TIMEOUT}" rac session list --cluster="${CURR_CLSTR%%,*}" \
            ${RAS_AUTH} "${HOSTNAME}:${RAS_PORT}" 2>/dev/null | \
            awk -F':' '/^(infobase|app-id|hibernate|duration-current|user-name|session-id)\s/ \
                { if ( $1 ~ "session-id" ) { print "<nl>"; }; print $2; }' |
            perl -pe 's/^[ ]+//; s/\n/|/; s/<nl>/\n/; s/(1CV8[^|]*|WebClient)/cl/; s/BackgroundJob/bg/;
                s/WSConnection/ws/; s/HTTPServiceConnection/hs/' | grep -v "^$" | sed -r "s/^\|//" |
            awk -v cluster="CL#${CURR_CLSTR%%,*}" -v ib_cache="${IB_CACHE}" -F'|' 'BEGIN {
                ss[cluster]=0;
                while ( getline ib_str < ib_cache > 0) {
                    if (ib_str ~ "^"substr(cluster,4)) {
                        split(ib_str, ib_uuid, " "); ss["IB#"ib_uuid[2]]=0; }
                } }
                { ib_mark="IB#"$2;
                ss[cluster]+=1; ss[ib_mark]+=1;
                if ( $4 != "cl" ) { sc[$4,cluster]+=1; sc[$4,ib_mark]+=1; }
                if ( $5 == "yes" ) { sc["hb",cluster]+=1; sc["hb",ib_mark]+=1 }
                if ( $6 != 0) {
                    as[cluster]+=1; as[ib_mark]+=1;
                    if ( asd[$4,cluster] < $6 ) {
                        asd[$4,cluster]=$6; asd[$4,ib_mark]=$6;
			if ( $4 == "cl" ) { asu[ib_mark]=$3" ("$1")"; }
                    } else if ( asd[$4,ib_mark] < $6 ) { asd[$4,ib_mark]=$6;
			if ( $4 == "cl" ) { asu[ib_mark]=$3" ("$1")"; }
	            }
                } }
                END { for (i in ss) {
                    print i":"(ss[i]?ss[i]:0)":"(sc["bg",i]?sc["bg",i]:0)":"(sc["hb",i]?sc["hb",i]:0)":"\
                        (sc["ws",i]?sc["ws",i]:0)":"(sc["hs",i]?sc["hs",i]:0)":"(as[i]?as[i]:0)":"\
                        (asd["cl",i]?asd["cl",i]:0)":"(asd["bg",i]?asd["bg",i]:0)":"\
                        (asd["ws",i]?asd["ws",i]:0)":"(asd["hs",i]?asd["hs",i]:0)":"asu[i] } }'
    done

}

function get_session_amounts {

    check_clusters_cache

    ( execute_tasks get_clusters_sessions $( pop_clusters_list self ) ) | \
        awk -F: '{ print $0; 
            if ($1 !~ /^IB/) { sc["all"]+=$2; sc["bg"]+=$3; sc["hb"]+=$4; sc["ws"]+=$5; sc["hs"]+=$6; sc["as"]+=$7;
                if ( asd["cl"] < $8 ) { asd["cl"]=$8; } 
                if ( asd["bg"] < $9 ) { asd["bg"]=$9; } 
                if ( asd["ws"] < $10 ) { asd["ws"]=$10; } 
                if ( asd["hs"] < $11 ) { asd["hs"]=$11; } 
            } } 
            END { print "summary:"(sc["all"]?sc["all"]:0)":"(sc["bg"]?sc["bg"]:0)":"(sc["hb"]?sc["hb"]:0)":"\
                (sc["ws"]?sc["ws"]:0)":"(sc["hs"]?sc["hs"]:0)":"(sc["as"]?sc["as"]:0)":"(asd["cl"]?asd["cl"]:0)":"\
                (asd["bg"]?asd["bg"]:0)":"(asd["ws"]?asd["ws"]:0)":"(asd["hs"]?asd["hs"]:0) }' | sed 's/<sp>/ /g'

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
    clusters) get_clusters_list ;;
    ib_restrict) get_infobases_restrictions ;;
    *) error "${ERROR_UNKNOWN_MODE}" ;;
esac

