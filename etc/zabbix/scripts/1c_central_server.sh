#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (центральный сервер)
#
# (c) 2020, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

WORK_DIR=$(dirname "${0}" | sed -r 's/\\/\//g; s/^(.{1}):/\/\1/')
source "${WORK_DIR}"/1c_common_module.sh || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

function get_infobase_status {
    curl -u "${2}:${3}" --header "SOAPAction: http://www.1c.ru/SSL/RemoteControl_1_0_0_1#RemoteControl:GetCurrentState" \
        -d '<env:Envelope xmlns:env="http://www.w3.org/2003/05/soap-envelope"
        xmlns:ns1="http://www.1c.ru/SSL/RemoteControl_1_0_0_1"><env:Body><ns1:GetCurrentState/>
        </env:Body></env:Envelope>' ${1}/ws/RemoteControl | perl -pe 's/.*m:return[^>]+>(\w+)<.*/\1/'
}

function get_infobases_list {

    CLUSTERS_LIST=$( pop_clusters_list self )
    BASE_INFO='{"data":[ '
    for CURRENT_CLUSTER in ${CLUSTERS_LIST//;/ }; do
        BASE_LIST=$(timeout -s HUP ${RAS_PARAMS[timeout]} rac infobase summary list \
            --cluster ${CURRENT_CLUSTER%%,*} ${RAS_PARAMS[auth]} ${HOSTNAME}:${RAS_PARAMS[port]} | \
            grep -Pe '(infobase|name)' | \
            perl -pe 's/[ "]//g; s/^name:(.*)$/\1\n/; s/^infobase:(.*)/\1,/; s/\n//' | perl -pe 's/\n/;/' )
        for CURRENT_BASE in ${BASE_LIST//;/ }; do
            BASE_INFO+="{ \"{#CLSTR_UUID}\":\"${CURRENT_CLUSTER%%,*}\",\"{#CLSTR_NAME}\":\"${CURRENT_CLUSTER##*,}\",\"{#IB_UUID}\":\"${CURRENT_BASE%,*}\",\"{#IB_NAME}\":\"${CURRENT_BASE#*,}\" }, "
        done
    done
    echo "${BASE_INFO%, } ]}" | sed 's/<sp>/ /g'
}

function get_clusters_list {

    [[ ! -f ${CLSTR_CACHE} ]] && error "Не найден файл списка кластеров!"

    grep -i "^${HOSTNAME}" ${CLSTR_CACHE} | cut -f2 -d: | \
        perl -pe 's/;[^\n]/\n/; s/;//' | \
        awk 'BEGIN {FS=","; print "{\"data\":[" } \
            {print "{\"{#CLSTR_UUID}\":\""$1"\",\"{#CLSTR_NAME}\":"$3"}," } \
            END { print "]}" }' | \
        perl -pe 's/\n//;' | perl -pe 's/(.*),]}/\1]}\n/'

}

function get_clusters_sessions {
    for CURR_CLSTR in ${1//;/ }; do
        timeout -s HUP ${RAS_PARAMS[timeout]} rac session list --cluster=${CURR_CLSTR%%,*} \
            ${RAS_PARAMS[auth]} ${HOSTNAME}:${RAS_PARAMS[port]} 2>/dev/null | \
            grep -Pe "^(infobase|app-id|hibernate)\s" | \
            perl -pe 's/ //g; s/\n/ /; s/infobase:/\n/; s/.*://' | grep -v "^$" | \
            awk -v cluster=${CURR_CLSTR##*,} '{ 
                ib_mark="UUID#"$1;
                sc[cluster]+=1; sc[ib_mark]+=1; 
                switch ( $2 ) { 
                    case "BackgroundJob":
                        bg[cluster]+=1; bg[ib_mark]+=1
                        break
                    case "WSConnection":
                        ws[cluster]+=1; ws[ib_mark]+=1
                        break
                    case "HTTPServiceConnection":
                        hs[cluster]+=1; hs[ib_mark]+=1
                        break
                    }
                if ( $3 == "yes" ) { hc[cluster]+=1; hc[ib_mark]+=1 } }
                END { for (i in sc) { 
                    print i":"(sc[i]?sc[i]:0)":"(bg[i]?bg[i]:0)":"(hc[i]?hc[i]:0)":"(ws[i]?ws[i]:0)":"(hs[i]?hs[i]:0) } }'
    done
}

function get_session_amounts {

    ( execute_tasks get_clusters_sessions $( pop_clusters_list self ) ) | \
        awk -F: 'BEGIN {sc=0; hc=0; bg=0; ws=0; hs=0 } 
           { print $0; 
           if ($1 !~ /^UUID/) {sc+=$2; bg+=$3; hc+=$4; ws+=$5; hs+=$6 } } 
           END { print "summary:"sc":"bg":"hc":"ws":"hs }' | sed 's/<sp>/ /g'

}


case ${1} in
    ib_status) shift; get_infobase_status ${@} ;;
    sessions) shift; make_ras_params ${@}; get_session_amounts ;;
    infobases) shift 2; make_ras_params ${@}; get_infobases_list ;;
    clusters) get_clusters_list ;;
    *) error "${ERROR_UNKNOWN_MODE}" ;;
esac

