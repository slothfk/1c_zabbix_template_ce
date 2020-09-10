# Что делать, если у меня MS Windows?

Не смотря на то, что изначально шаблон создавался для платформы GNU/Linux, в файлы скриптов были внесены необходимымые изменения, которые позволяют использовать их на платформе MS Windows.

## Что необходимо сделать?

* Установить на сервер, который требуется мониторить, **Git Bash** - https://gitforwindows.org/
* Поместить файлы **userparameter_1c-*.conf** из каталога **etc/zabbix/zabbix_agentd.d** в каталог **C:\Program Files\Zabbix Agent\zabbix_agentd.conf.d** (или в какой другой, куда установлен **zabbix-agent**)
* Поместить файлы скриптов ***.sh** из каталога **etc/zabbix/scripts** в каталог, к примеру, **C:\Program Files\Zabbix Agent\scripts**
* Внести правки в файлы **userparameter_1c-*.conf** в части строки вызова скриптов, заменив в каждой строке вызов срипта по аналогии с
<pre>/etc/zabbix/scripts/1c_central_server.sh</pre>
на следующее
<pre>"C:\Program Files\Git\bin\bash.exe" "C:\Program Files\Zabbix Agent\scripts\1c_central_server.sh"</pre>
обязательно заключая пути в кавычки!

Все остальные настройки, касающиеся агента и сервера **Zabbix** делаются ка написано [здесь](./install.md)

[Назад](../README.md)
