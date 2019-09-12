#!/bin/bash

/usr/bin/zabbix_sender -c /etc/zabbix/zabbix_agentd.conf -k 1c.rmngr.license -o $(/etc/zabbix/scripts/1c_rmngr_license.sh info) > /dev/null