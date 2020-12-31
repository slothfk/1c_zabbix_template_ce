#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (центральный сервер)
#
# (c) 2020, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

WORK_DIR=$(dirname "${0}" | sed -r 's/\\/\//g; s/^(.{1}):/\/\1/')
source "${WORK_DIR}"/1c_common_module.sh 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

# Файл списка информационных баз
IB_CACHE=${TMPDIR}/1c_infobase_cache

function get_infobase_status {
    curl -u "${2}:${3}" --header "SOAPAction: http://www.1c.ru/SSL/RemoteControl_1_0_0_1#RemoteControl:GetCurrentState" \
        -d '<env:Envelope xmlns:env="http://www.w3.org/2003/05/soap-envelope"
        xmlns:ns1="http://www.1c.ru/SSL/RemoteControl_1_0_0_1"><env:Body><ns1:GetCurrentState/>
        </env:Body></env:Envelope>' ${1}/ws/RemoteControl | perl -pe 's/.*m:return[^>]+>(\w+)<.*/\1/'
}

function get_infobases_list {

    cat /dev/null > ${IB_CACHE}

    CLUSTERS_LIST=$( pop_clusters_list self )
    BASE_INFO='{"data":[ '
    for CURRENT_CLUSTER in ${CLUSTERS_LIST//;/ }; do
        BASE_LIST=$(timeout -s HUP ${RAS_PARAMS[timeout]} rac infobase summary list \
            --cluster ${CURRENT_CLUSTER%%,*} ${RAS_PARAMS[auth]} ${HOSTNAME}:${RAS_PARAMS[port]} | \
            awk '/(infobase|name)/' | \
            perl -pe 's/[ "]//g; s/^name:(.*)$/\1\n/; s/^infobase:(.*)/\1,/; s/\n//' | perl -pe 's/\n/;/' )
        for CURRENT_BASE in ${BASE_LIST//;/ }; do
            BASE_INFO+="{ \"{#CLSTR_UUID}\":\"${CURRENT_CLUSTER%%,*}\",\"{#CLSTR_NAME}\":\"${CURRENT_CLUSTER##*,}\",\"{#IB_UUID}\":\"${CURRENT_BASE%,*}\",\"{#IB_NAME}\":\"${CURRENT_BASE#*,}\" }, "
            echo "${CURRENT_CLUSTER%%,*} ${CURRENT_BASE%,*}" >> ${IB_CACHE}
        done
    done
    echo "${BASE_INFO%, } ]}" | sed 's/<sp>/ /g'
}

function get_clusters_list {

    pop_clusters_list self | perl -pe 's/;[^\n]/\n/; s/;//' | \
        awk 'BEGIN {FS=","; print "{\"data\":[" } \
            {print "{\"{#CLSTR_UUID}\":\""$1"\",\"{#CLSTR_NAME}\":\""$3"\"}," } \
            END { print "]}" }' | \
        perl -pe 's/\n//;' | perl -pe 's/(.*),]}/\1]}\n/; s/<sp>/ /g'

}

function get_clusters_sessions {

    for CURR_CLSTR in ${1//;/ }; do
        timeout -s HUP ${RAS_PARAMS[timeout]} rac session list --cluster=${CURR_CLSTR%%,*} \
            ${RAS_PARAMS[auth]} ${HOSTNAME}:${RAS_PARAMS[port]} 2>/dev/null | \
            awk '/^(infobase|app-id|hibernate|duration-current)\s/' | \
            perl -pe 's/ //g; s/\n/ /; s/infobase:/\n/; s/.*://; s/(1CV8[^ ]*|WebClient)/cl/; 
                s/BackgroundJob/bg/; s/WSConnection/ws/; s/HTTPServiceConnection/hs/' | grep -v "^$" | \
            awk -v cluster="CL#${CURR_CLSTR%%,*}" -v ib_cache="${IB_CACHE}" 'BEGIN {
                ss[cluster]=0;
                while ( getline ib_str < ib_cache > 0) {
                    if (ib_str ~ "^"substr(cluster,4)) { split(ib_str, ib_uuid);
                        i="IB#"ib_uuid[2]; ss[i]=0; as[i]=0;
                        sc["bg",i]=0; sc["hb",i]=0; sc["ws",i]=0; sc["hs",i]=0;
                        asd["cl",i]=0; asd["bg",i]=0; asd["ws",i]=0; asd["hs",i]=0 }
                } }
                { ib_mark="IB#"$1;
                ss[cluster]+=1; ss[ib_mark]+=1; 
                if ( $2 != "cl" ) { sc[$2,cluster]+=1; sc[$2,ib_mark]+=1; }
                if ( $3 == "yes" ) { sc["hb",cluster]+=1; sc["hb",ib_mark]+=1 } 
                if ( $4 != 0) { 
                    as[cluster]+=1; as[ib_mark]+=1; 
                    if ( asd[$2,cluster] < $4 ) { 
                        asd[$2,cluster]=$4; asd[$2,ib_mark]=$4; 
                    } else if ( asd[$2,ib_mark] < $4 ) { asd[$2,ib_mark]=$4; }
                } }
                END { for (i in ss) { 
                    print i":"(ss[i]?ss[i]:0)":"(sc["bg",i]?sc["bg",i]:0)":"(sc["hb",i]?sc["hb",i]:0)":"\
                        (sc["ws",i]?sc["ws",i]:0)":"(sc["hs",i]?sc["hs",i]:0)":"(as[i]?as[i]:0)":"\
                        (asd["cl",i]?asd["cl",i]:0)":"(asd["bg",i]?asd["bg",i]:0)":"\
                        (asd["ws",i]?asd["ws",i]:0)":"(asd["hs",i]?asd["hs",i]:0) } }'
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


case ${1} in
    ib_status) shift; get_infobase_status ${@} ;;
    sessions) shift; make_ras_params ${@}; get_session_amounts ;;
    infobases) shift 2; make_ras_params ${@}; get_infobases_list ;;
    clusters) get_clusters_list ;;
    *) error "${ERROR_UNKNOWN_MODE}" ;;
esac

