#!/bin/bash

/usr/bin/zabbix_sender -c /etc/zabbix/zabbix_agentd.conf -k 1c.ls.licenses -o $(nice -n 19 /etc/zabbix/scripts/1c_license_server.sh info) > /dev/null
