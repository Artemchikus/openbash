#!/bin/bash

#source ~/openstack-init.sh

RABBIT_PASS=""
KEYSTONE_PASS=""
ADMIN_PASS=""
GLANCE_PASS=""
NEUTRON_PASS=""
NOVA_HOSTNAME=""
NOVA_PASS=""
PLACEMENT_PASS=""
METADATA_SECRET=""
DB_PASS=""
CINDER_PASS=""
NOVA_IP=""
NEUTRON_IP=""
HOST_IP=""
NFS_HOSTNAME=""
TIME_ZONE=""
GNOCCHI_PASS=""
GNOCCHI_HOSTNAME=""
CEILOMETER_PASS=""
AODH_PASS=""
AODH_HOSTNAME=""
HEAT_PASS=""
HEAT_HOSTNAME=""
BARBICAN_PASS=""
MANILA_PASS=""
DESIGNATE_PASS=""
DESIGNATE_HOSTNAME=""
OCTAVIA_PASS=""
OCTAVIA_HOSTNAME=""
MAGNUM_PASS=""
MAGNUM_HOSTNAME=""
RALLY_PASS=""
KITTY_PASS=""
KITTY_HOSTNAME=""
NOVA_IP=""
DNS=""
HOSTNAME=""
HOST_NETWORK=""

values_menu=(
"Пароль от сервиса RabbitMQ"
""
"Пароль от сервиса Keystone"
""
"Пароль админа Openstack"
""
"Пароль от сервиса Glance"
""
"Пароль от сервиса Neutron"
""
"Имя узла, на котором находится сервис Nova"
""
"Пароль от сервиса Nova"
""
"Пароль от сервиса Placement"
""
"Секрет для обмена метаданными между узлами"
""
"Пароль от Базы данных MariaDB"
""
"Пароль от сервиса Cinder"
""
"Ip-адрес узла, на котором находится сервис Nova"
""
"Имя nfs-сервер узла"
""
"Пароль от сервиса Gnocchi"
""
"Имя узла, на котором находится сервис Gnocchi"
""
"Пароль от сервиса Ceilometer"
""
"Пароль от сервиса Aodh"
""
"Имя узла, на котором находится сервис Aodh"
""
"Пароль от сервиса Heat"
""
"Имя узла, на котором находится сервис Heat"
""
"Пароль от сервиса Barbican"
""
"Пароль от сервиса Manila"
""
"Пароль от сервиса Designate"
""
"Имя узла, на котором находится сервис Designate"
""
"Пароль от сервиса Octavia"
""
"Имя узла, на котором находится сервис Octavia"
""
"Пароль от сервиса Magnum"
""
"Имя узла, на котором находится сервис Magnum"
""
"Пароль от сервиса Rally"
""
"Пароль от сервиса CloudKitty"
""
"Имя узла, на котором находится сервис CloudKitty"
""
"Имя узла в формате [<controller>.>test>.<local>]"
""
"IP адрес узла на котром находится neutron-server"
""
)

node_type_menu=(
"Управляющий узел"
""
"Рабочий узел"
""
"Сетевой узел"
""
"Узел хранения"
""
"Узел с nfs-сервером"
""
)

service_menu=(
"RabbitMQ - брокер сообщений (обязательный)"
"1"
"MariaDB - база метаданных (обязательная)"
"1"
"Nginx - прокси сервер (обязательный)"
"1"
"Keystone - регистрация/аутентификация пользователей и сервисов (обязательный)"
"1"
"Glance - управление образами [обязательный]"
"1"
"Nova и Placement - управление ВМ [обязательный]"
"1"
"Neutron - управление сетями [обязательный]"
"1"
"Cinder - управление постоянными томами [обязательнй]"
"1"
"Horizon - веб интерфейс кластера"
""
"Telemetry (Gnocchi + Ceilometer + Aodh) - управление метриками"
""
"Heat - оркестрация ВМ"
""
"Barbican - управление секретами"
""
"Manila - управление общими файловыми системами"
""
"Designate - управление DNS"
""
"Octavia - управление балансировщиками нагрузки"
""
"Magnum - управление инфраструктурой контейнеров"
""
"Rally - тестирование масштабируемости кластера"
""
"CloudKitty - оценивание на основе метрик"
""
)

NODE_TYPE="" 
MENU_TYPE="scheme"

function display_node_values_menu() {
    clear

    echo "Заполните все параметры для дальнейшей конфигурации сервисов:"

    local true_index=0
    for (( i=0; i<${#values_menu[@]}; i=i+2 )); do
        if [[ "${values_menu[$i+1]}" == "1" ]]; then
            true_index="$(expr $true_index + 1)"
            echo "  [ ] $((true_index)). ${values_menu[$i]}"
        elif [[ "${values_menu[$i+1]}" ]]; then
            true_index="$(expr $true_index + 1)"
            echo "  [x] $((true_index)). ${values_menu[$i]} (${values_menu[$i+1]})"
        fi
    done

    read -p "Введите номер или c (продолжить), b (вернуться), q (выйти): " choice

    if ! [[ "$choice" =~ ^[0-9]+$|^c$|^b$|^q$ ]]; then
        echo "Неправильный ввод: $choice"
        sleep 2
    elif [ "$choice" == "c" ]; then
        MENU_TYPE="start"
        for (( i=1; i<${#values_menu[@]}; i=i+2 )); do
            if [ "${values_menu[$i]}" == "1" ]; then
            	echo "Введите значение: ${values_menu[$i-1]}"
                sleep 2
                MENU_TYPE="node_values"
                break
            fi
        done
    elif [ "$choice" == "b" ]; then
        for (( i=0; i<${#values_menu[@]}; i=i+2 )); do
             values_menu[$i+1]=""
        done
        MENU_TYPE="services"
    elif [ "$choice" == "q" ]; then
    	read -p "Вы уверены? (y/n)" yes
    	if ! [[ "$yes" =~ ^n$|^y$ ]]; then
            echo "Неправильный ввод: $yes"
            sleep 2
        elif [ "$yes" == "y" ]; then
            echo "До свидания!"
            exit 0
        fi
    elif (( choice < 1 || choice > $true_index )); then
        echo "Неправильный ввод: $choice"
        sleep 2
    else
    	local true_index=0
        for (( i=0; i<${#values_menu[@]}; i=i+2 )); do
            if [[ "${values_menu[$i+1]}" ]]; then
                true_index="$(expr $true_index + 1)"
                if [[ "$true_index" == "$choice" ]]; then
                    choice="$i"
                    break
                fi
            fi
        done
        read -p "${values_menu[$((choice))]}: " value
        if [ "$value" == "" ]; then
            echo "Неправильный ввод: $value"
            sleep 2
        else
            values_menu[$choice+1]="$value"
        fi
    fi
    display_menu
}

function display_node_type_menu() {
    clear

    echo "Выберите тип узла:"

    for (( i=0; i<${#node_type_menu[@]}; i=i+2 )); do
        if [[ "${node_type_menu[$i+1]}" ]]; then
            echo "  [x] $((i/2+1)). ${node_type_menu[$i]}"
        else
            echo "  [ ] $((i/2+1)). ${node_type_menu[$i]}"
        fi
    done

    read -p "Введите номер или c (продолжить), b (вернуться), q (выйти): " choice

    if ! [[ "$choice" =~ ^[0-9]+$|^c$|^b$|^q$ ]]; then
        echo "Неправильный ввод: $choice"
        sleep 2
    elif [ "$choice" == "c" ]; then
    	if [ "$NODE_TYPE" != "" ]; then
            MENU_TYPE="services"
        else
             echo "Вы не выбрали тип узла!"
             sleep 2
        fi
    elif [ "$choice" == "b" ]; then
        MENU_TYPE="scheme"
    elif [ "$choice" == "q" ]; then
        read -p "Вы уверены? (y/n)" yes
    	if ! [[ "$yes" =~ ^n$|^y$ ]]; then
            echo "Неправильный ввод: $yes"
            sleep 2
        elif [ "$yes" == "y" ]; then
            echo "До свидания!"
            exit 0
        fi
    elif (( choice < 1 || choice > ${#node_type_menu[@]}/2 )); then
        echo "Неправильный ввод: $choice"
        sleep 2
    else
	for (( i=0; i<${#node_type_menu[@]}; i=i+2 )); do
            node_type_menu[$i+1]=""
        done
	node_type_menu[$((choice*2-1))]="1"
	NODE_TYPE="$choice"
    fi
    display_menu
}

function display_service_chose_menu() {
    clear

    echo "Выберите сервисы, которые планируются к разворачивании во всем кластере (не только на выбранном узле):"

    for (( i=0; i<${#service_menu[@]}; i=i+2 )); do
        if [[ "${service_menu[$i+1]}" ]]; then
            echo "  [x] $((i/2+1)). ${service_menu[$i]}"
        else
            echo "  [ ] $((i/2+1)). ${service_menu[$i]}"
        fi
    done

    read -p "Введите номер или c (продолжить), b (вернуться), q (выйти): " choice
    
    if ! [[ "$choice" =~ ^[0-9]+$|^c$|^b$|^q$ ]]; then
	echo "Неправильный ввод: $choice"
	sleep 2
    elif [ "$choice" == "c" ]; then
    	generate_values
	MENU_TYPE="node_values"
    elif [ "$choice" == "b" ]; then
	MENU_TYPE="node_type"
    elif [ "$choice" == "q" ]; then
	read -p "Вы уверены? (y/n)" yes
    	if ! [[ "$yes" =~ ^n$|^y$ ]]; then
            echo "Неправильный ввод: $yes"
            sleep 2
        elif [ "$yes" == "y" ]; then
            echo "До свидания!"
            exit 0
        fi
    elif (( choice < 1 || choice > ${#service_menu[@]}/2 )); then
	echo "Неправильный ввод: $choice"
	sleep 2
    elif [[ "${service_menu[$((choice*2-1))]}" == "1" ]]; then
	service_menu[$((choice*2-1))]=""
	if (( choice <= 8 )); then
	    echo "Если данный сервис уже не установлен, то могут быть проблемы в настройке других сервисов"
	    sleep 3
	fi
    else
	service_menu[$((choice*2-1))]="1"
    fi
    display_menu
}

function display_cluster_scheme() {
clear
echo "Схема кластера на котором все тестировалось:"
cat << EOF
----------------+-----------------------------------+-------------------------------+------------
                |                                   |                               |
          enp1s0|192.168.122.20               enp1s0|192.168.122.22           enp1s0|192.168.122.21
+---------------+---------------+     +-------------+------------+     +------------+-----------+
|   [ controller.test.local ]   |     |  [ network.test.local ]  |     | [ compute.test.local ] |
|        (Control Node)         |     |      (Network Node)      |     |     (Compute Node)     |
|                               |     |                          |     |                        |
|  MariaDB      RabbitMQ        |     |       Open vSwitch       |     |        Libvirt         |
|  Memcached    Nginx           |     |      Neutron Server      |     |      Nova Compute      |
|  Keystone     httpd           |     |        OVN-Northd        |     |      Open vSwitch      |
|  Glance       Nova API        |     |   Nginx   iSCSI Target   |     |   OVN Metadata Agent   |
|  Cinder API   Horizon         |     |   Cinder Volume/Backup   |     |     OVN-Controller     |
|  Rally        Barbican API    |     |  httpd  Magnum Services  |     |   Ceilometer Compute   |
|  Manila API                   |     |  Gnocchi   Manila Share  |     |       NFS Server       |             
|                               |     |   CloudKitty API  Aodh   |     |                        |
|                               |     |      Heat API/Engine     |     |                        |
|                               |     |     Octavia Services     |     |                        |
|                               |     |    Designate Services    |     |                        |
|                               |     |    Ceilometer Central    |     |                        |
+-------------------------------+     +-------------+------------+     +------------+-----------+
                                              enp2s0|(bridge)                 enp2s0|(bridge)
EOF
read -p "c (продолжить), q (выйти): " choice
    
    if ! [[ "$choice" =~ ^c$|^q$ ]]; then
	echo "Неправильный ввод: $choice"
	sleep 2
    elif [ "$choice" == "c" ]; then
        MENU_TYPE="node_type"
    else
	read -p "Вы уверены? (y/n)" yes
    	if ! [[ "$yes" =~ ^n$|^y$ ]]; then
            echo "Неправильный ввод: $yes"
            sleep 2
        elif [ "$yes" == "y" ]; then
            echo "До свидания!"
            exit 0
        fi
    fi
    display_menu
}

function generate_values() {
    case $NODE_TYPE in
    "1")
      generate_controller_node_values
      ;;
    "2")
      generate_compute_node_values
      ;;
    "3")
      generate_network_node_values
      ;;
    "4")
      generate_storage_node_values
      ;;
    "5")
      generate_nfs_server_values
      ;;
    *)
      exit 0
      ;;
    esac
}

function generate_controller_node_values() {
#node-values
values_menu[19]="1" #DB_PASS
values_menu[63]="1" #HOSTNAME

for (( i=0; i<${#service_menu[@]}; i=i+2 )); do
        if [[ "${service_menu[$i+1]}" == "1" ]]; then
            service_choose="$(expr $i + 1)"
            parse_controller "$service_choose"
        fi
done
}

function parse_controller() {
local service_choose=("$@")

if [[ "$service_choose" == "1" ]]; then
#rabbit-values
values_menu[1]="1" #RABBIT_PASS
elif [[ "$service_choose" == "7" ]]; then
#keystone-values
values_menu[3]="1" #KEYSTONE_PASS
values_menu[5]="1" #ADMIN_PASS
elif [[ "$service_choose" == "9" ]]; then
#glance-values
values_menu[7]="1" #GLANCE_PASS
elif [[ "$service_choose" == "11" ]]; then
#nova-values
values_menu[13]="1" #NOVA_PASS
values_menu[15]="1" #PLACEMENT_PASS
elif [[ "$service_choose" == "13" ]]; then
#neutron-values
values_menu[9]="1" #NEUTRON_PASS
values_menu[17]="1" #METADATA_SECRET
elif [[ "$service_choose" == "15" ]]; then
#cinder-values
values_menu[21]="1" #CINDER_PASS
elif [[ "$service_choose" == "19" ]]; then
#telemetry-values
values_menu[27]="1" #GNOCCHI_PASS
values_menu[29]="1" #GNOCCHI_HOSTNAME
values_menu[31]="1" #CEILOMETER_PASS
values_menu[33]="1" #AODH_PASS
values_menu[35]="1" #AODH_HOSTNAME
values_menu[7]="1" #GLANCE_PASS
values_menu[21]="1" #CINDER_PASS
elif [[ "$service_choose" == "21" ]]; then
#heat-values
values_menu[37]="1" #HEAT_PASS
values_menu[39]="1" #HEAT_HOSTNAME
elif [[ "$service_choose" == "23" ]]; then
#barbican-values
values_menu[41]="1" #BARBICAN_PASS
elif [[ "$service_choose" == "25" ]]; then
#manila-values
values_menu[43]="1" #MANILA_PASS
elif [[ "$service_choose" == "27" ]]; then
#designate-values
values_menu[45]="1" #DESIGNATE_PASS
values_menu[47]="1" #DESIGNATE_HOSTNAME
elif [[ "$service_choose" == "29" ]]; then
#octavia-values
values_menu[49]="1" #OCTAVIA_PASS
values_menu[51]="1" #OCTAVIA_HOSTNAME
elif [[ "$service_choose" == "31" ]]; then
#magnum-values
values_menu[53]="1" #MAGNUM_PASS
values_menu[55]="1" #MAGNUM_HOSTNAME
elif [[ "$service_choose" == "33" ]]; then
#rally-values
values_menu[57]="1" #RALLY_PASS
elif [[ "$service_choose" == "35" ]]; then
#cloudkitty-values
values_menu[59]="1" #KITTY_PASS
values_menu[61]="1" #KITTY_HOSTNAME
fi
}

function  generate_compute_node_values() {
#node-values
values_menu[63]="1" #HOSTNAME
values_menu[11]="1" #NOVA_HOSTNAME

for (( i=0; i<${#service_menu[@]}; i=i+2 )); do
        if [[ "${service_menu[$i+1]}" == "1" ]]; then
            service_choose="$(expr $i + 1)"
            parse_compute "$service_choose"
        fi
done
}

function parse_compute() {
local service_choose=("$@")

if [[ "$service_choose" == "11" ]]; then
#nova-values
values_menu[13]="1" #NOVA_PASS
values_menu[15]="1" #PLACEMENT_PASS
elif [[ "$service_choose" == "13" ]]; then
#neutron-values
values_menu[9]="1" #NEUTRON_PASS
values_menu[65]="1" #NEUTRON_IP
values_menu[17]="1" #METADATA_SECRET
elif [[ "$service_choose" == "19" ]]; then
#telemetry-values
values_menu[31]="1" #CEILOMETER_PASS
fi
}

function generate_network_node_values() {
#node-values
values_menu[63]="1" #HOSTNAME
values_menu[11]="1" #NOVA_HOSTNAME

for (( i=0; i<${#service_menu[@]}; i=i+2 )); do
        if [[ "${service_menu[$i+1]}" == "1" ]]; then
            service_choose="$(expr $i + 1)"
            parse_network "$service_choose"
        fi
done
}

function parse_network() {
local service_choose=("$@")

if [[ "$service_choose" == "13" ]]; then
#neutron-values
values_menu[9]="1" #NEUTRON_PASS
values_menu[17]="1" #METADATA_SECRET
elif [[ "$service_choose" == "19" ]]; then
#telemetry-values
values_menu[27]="1" #GNOCCHI_PASS
values_menu[31]="1" #CEILOMETER_PASS
values_menu[33]="1" #AODH_PASS
elif [[ "$service_choose" == "21" ]]; then
#heat-values
values_menu[37]="1" #HEAT_PASS
elif [[ "$service_choose" == "27" ]]; then
#designate-values
values_menu[45]="1" #DESIGNATE_PASS
elif [[ "$service_choose" == "29" ]]; then
#octavia-values
values_menu[49]="1" #OCTAVIA_PASS
elif [[ "$service_choose" == "31" ]]; then
#magnum-values
values_menu[53]="1" #MAGNUM_PASS
elif [[ "$service_choose" == "35" ]]; then
#cloudkitty-values
values_menu[59]="1" #KITTY_PASS
fi
}

function generate_storage_node_values() {
#node-values
values_menu[63]="1" #HOSTNAME
values_menu[11]="1" #NOVA_HOSTNAME

for (( i=0; i<${#service_menu[@]}; i=i+2 )); do
        if [[ "${service_menu[$i+1]}" == "1" ]]; then
            service_choose="$(expr $i + 1)"
            parse_storage "$service_choose"
        fi
done
}

function parse_storage() {
local service_choose=("$@")

if [[ "$service_choose" == "15" ]]; then
#cinder-values
values_menu[21]="1" #CINDER_PASS
values_menu[25]="1" #NFS_HOSTNAME
elif [[ "$service_choose" == "25" ]]; then
#manila-values
values_menu[43]="1" #MANILA_PASS
fi
}

function generate_nfs_server_values() {
#node-values
values_menu[63]="1" #HOSTNAME
values_menu[11]="1" #NOVA_HOSTNAME
}

function display_menu() {
    case $MENU_TYPE in
    "node_type")
      display_node_type_menu
      ;;
    "node_values")
      display_node_values_menu
      ;;
    "services")
      display_service_chose_menu
      ;;
    "scheme")
      display_cluster_scheme
      ;;
    "start")
      start_deploy
      ;;
    *)
      exit 0
      ;;
    esac
}

function start_deploy() {

fill_envs
check

read -p "Начать загрузку? (y/n)" choice
    if ! [[ "$choice" =~ ^y$|^n$ ]]; then
	echo "Неправильный ввод: $choice"
	sleep 2
    elif [ "$choice" == "y" ]; then
        check_node
        setup_steps
    elif [ "$choice" == "n" ]; then
        MENU_TYPE="node_values"
        display_menu
    fi
}

function fill_envs() {
HOST_IP="$(ip -f inet addr show enp1s0 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')"
HOSTNAME="${values_menu[63]}"
IFS=. read -r a b c <<< "$HOSTNAME"
DNS="$b.$c"
IFS=. read -r a b c d <<< "$HOST_IP"
HOST_NETWORK="$a.$b.$c.0"
TIME_ZONE="$(timedatectl | grep -Eo "[A-Za-z]+/[A-Za-z]+")"

RABBIT_PASS="${values_menu[1]}"
KEYSTONE_PASS="${values_menu[3]}"
ADMIN_PASS="${values_menu[5]}"
GLANCE_PASS="${values_menu[7]}"
NEUTRON_PASS="${values_menu[9]}"
if [[ "${values_menu[11]}" ]]; then
NOVA_HOSTNAME="${values_menu[11]}"
else
NOVA_HOSTNAME="$HOSTNAME"
fi
NOVA_PASS="${values_menu[13]}"
PLACEMENT_PASS="${values_menu[15]}"
METADATA_SECRET="${values_menu[17]}"
DB_PASS="${values_menu[19]}"
CINDER_PASS="${values_menu[21]}"
if [[ "${values_menu[23]}" ]]; then
NOVA_IP="${values_menu[23]}"
else
NOVA_IP="$HOST_IP"
fi
NFS_HOSTNAME="${values_menu[25]}"
GNOCCHI_PASS="${values_menu[27]}"
if [[ "${values_menu[29]}" ]]; then
GNOCCHI_HOSTNAME="${values_menu[29]}"
else
GNOCCHI_HOSTNAME="$HOSTNAME"
fi
CEILOMETER_PASS="${values_menu[31]}"
AODH_PASS="${values_menu[33]}"
if [[ "${values_menu[35]}" ]]; then
AODH_HOSTNAME="${values_menu[35]}"
else
AODH_HOSTNAME="$HOSTNAME"
fi
HEAT_PASS="${values_menu[37]}"
if [[ "${values_menu[39]}" ]]; then
HEAT_HOSTNAME="${values_menu[39]}"
else
HEAT_HOSTNAME="$HOSTNAME"
fi
BARBICAN_PASS="${values_menu[41]}"
MANILA_PASS="${values_menu[43]}"
DESIGNATE_PASS="${values_menu[45]}"
if [[ "${values_menu[47]}" ]]; then
DESIGNATE_HOSTNAME="${values_menu[47]}"
else
DESIGNATE_HOSTNAME="$HOSTNAME"
fi
OCTAVIA_PASS="${values_menu[49]}"
if [[ "${values_menu[51]}" ]]; then
OCTAVIA_HOSTNAME="${values_menu[51]}"
else
OCTAVIA_HOSTNAME="$HOSTNAME"
fi
MAGNUM_PASS="${values_menu[53]}"
if [[ "${values_menu[55]}" ]]; then
MAGNUM_HOSTNAME="${values_menu[55]}"
else
MAGNUM_HOSTNAME="$HOSTNAME"
fi
RALLY_PASS="${values_menu[57]}"
KITTY_PASS="${values_menu[59]}"
if [[ "${values_menu[61]}" ]]; then
KITTY_HOSTNAME="${values_menu[61]}"
else
KITTY_HOSTNAME="$HOSTNAME"
fi
if [[ "${values_menu[65]}" ]]; then
NEUTRON_IP="${values_menu[65]}"
else
NEUTRON_IP="$HOST_IP"
fi
}

function check_node() {

echo -e "\033[1mПРОВЕРКА ПРИГОДНОСТИ УЗЛА\033[0m"

echo "Проверка доступа в интернет"

PING=$(ping google.com -c 3 | grep "packet loss" | grep -Eo "[0-9]+%" | grep -Eo "[0-9]+")
if [ "$PING" -eq "0" ]; then
echo "Доступ в интернет имеется"
else
echo "У любого узла должен быть доступ в интренет"
exit 1
fi

echo "Проверка ресурса CPU"

CORES=$(cat /proc/cpuinfo | grep processor | wc -l)
if [ "$CORES" -ge "2" ]; then
echo "vCPUS достаточно"
else
echo "Для любого узла нужно как минимум 2 vCPUS"
exit 1
fi

case $NODE_TYPE in
    "1")
      check_controll_node
      ;;
    "2")
      check_compute_node
      ;;
    "3")
      check_network_node
      ;;
    "4")
      check_storage_node
      ;;
    "5")
      check_nfs_server
      ;;
    *)
      exit 0
      ;;
esac
}


function check_controll_node() {

echo "Проверка ресурса дисков"

DISK=$(lsblk /dev/vda -o "SIZE,TYPE" | grep disk | grep -Eo "[0-9,]+")
if [ "$DISK" -ge "20" ]; then
echo "Свободного места достаточно"
else
echo "Для управляющего узла нужно как минимум 20 GB свободного места"
exit 1
fi

echo "Проверка ресурса оперативной памяти"

RAM=$(cat /proc/meminfo | grep "MemTotal" | grep -Eo "[0-9]+")
RAM=$(($RAM / 1048576))
if [ "$RAM" -ge "7" ]; then
echo "RAM достаточно"
else
echo "Для управляющего узла нужно как минимум 8 GB RAM"
exit 1
fi
}

function check_compute_node() {

echo "Проверка ресурса дисков"

DISK=$(lsblk /dev/vda -o "SIZE,TYPE" | grep disk | grep -Eo "[0-9,]+")
if [ "$DISK" -ge "10" ]; then
echo "Свободного места достаточно"
else
echo "Для рабочего узла нужно как минимум 10 GB свободного места"
exit 1
fi

echo "Проверка ресурса оперативной памяти"

RAM=$(cat /proc/meminfo | grep "MemTotal" | grep -Eo "[0-9]+")
RAM=$(($RAM / 1048576))
if [ "$RAM" -ge "3" ]; then
echo "RAM достаточно"
else
echo "Для рабочего узла нужно как минимум 4 GB RAM"
exit 1
fi

echo "Проверка поддержки виртуализации"

VIRT=$(grep -E "vmx|svm" /proc/cpuinfo | wc -l)
if [ "$VIRT" -gt "0" ]; then
echo "Узел поддерживает аппаратную виртуализацию"
else
echo "Для рабочего узла желательно аппаратная поддержка виртуализации (настройка через quemu в скрипте не предусмотрена)"
exit 1
fi

if [[ "${service_menu[13]}" == "1" ]]; then

echo "Проверка наличия двух сетевых интерфейсов (enp1s0 и enp*s0)"

ETH=$(ip a | grep -E "enp[0-9]s0:" | wc -l)
if [ "$ETH" -ge "2" ]; then
echo "Оба сетевых интерфейса присутствуют"
else
echo "У сетевого узла должны быть два сетевых интерфейса (enp1s0 и enp*s0)"
exit 1
fi

fi
}

function check_network_node() {

echo "Проверка ресурса дисков"

DISK=$(lsblk /dev/vda -o "SIZE,TYPE" | grep disk | grep -Eo "[0-9,]+")
if [ "$DISK" -ge "10" ]; then
echo "Свободного места достаточно"
else
echo "Для сетевого узла нужно как минимум 20 GB свободного места"
exit 1
fi

echo "Проверка ресурса оперативной памяти"

RAM=$(cat /proc/meminfo | grep "MemTotal" | grep -Eo "[0-9]+")
RAM=$(($RAM / 1048576))
if [ "$RAM" -ge "7" ]; then
echo "RAM достаточно"
else
echo "Для сетевого узла нужно как минимум 8 GB RAM"
exit 1
fi

if [[ "${service_menu[13]}" == "1" ]]; then

echo "Проверка наличия двух сетевых интерфейсов (enp1s0 и enp*s0)"

ETH=$(ip a | grep -E "enp[0-9]s0:" | wc -l)
if [ "$ETH" -ge "2" ]; then
echo "Оба сетевых интерфейса присутствуют"
else
echo "У сетевого узла должны быть два сетевых интерфейса (enp1s0 и enp*s0)"
exit 1
fi

fi
}

function check_storage_node() {

echo "Проверка ресурса дисков"

DISK=$(lsblk /dev/vda -o "SIZE,TYPE" | grep disk | grep -Eo "[0-9,]+")
if [ "$DISK" -ge "20" ]; then
echo "Свободного места достаточно"
else
echo "Для узла хранения нужно как минимум 20 GB свободного места"
exit 1
fi

echo "Проверка ресурса оперативной памяти"

RAM=$(cat /proc/meminfo | grep "MemTotal" | grep -Eo "[0-9]+")
RAM=$(($RAM / 1048576))
if [ "$RAM" -ge "3" ]; then
echo "RAM достаточно"
else
echo "Для управляющего/сетевого узла нужно как минимум 4 GB RAM"
exit 1
fi

if [[ "${service_menu[15]}" == "1" ]]; then

echo "Проверка наличия отдельного диска (vdb) для lvm-группы сервиса Cinder"

LVM=$(lsblk /dev/vdb | wc -l)
if [ "$LVM" -ne "0" ]; then
echo "Узел поддерживает аппаратную виртуализацию"
else
echo "Для управляющего узла нужен дополнительный диск (vdb) для lvm-группы сервиса Cinder"
exit 1
fi

fi

if [[ "${service_menu[25]}" == "1" ]]; then

echo "Проверка наличия отдельного диска (vdс) для lvm-группы cервиса Manila"

LVM=$(lsblk /dev/vdc | wc -l)
if [ "$LVM" -ne "0" ]; then
echo "Узел поддерживает аппаратную виртуализацию"
else
echo "Для управляющего узла нужен дополнительный диск (vdc) для lvm-группы cервиса Manila"
exit 1
fi

fi
}

function check_nfs_server_node() {

echo "Проверка ресурса дисков"

DISK=$(lsblk /dev/vda -o "SIZE,TYPE" | grep disk | grep -Eo "[0-9,]+")
if [ "$DISK" -ge "20" ]; then
echo "Свободного места достаточно"
else
echo "Для узла хранения нужно как минимум 20 GB свободного места"
exit 1
fi

echo "Проверка ресурса оперативной памяти"

RAM=$(cat /proc/meminfo | grep "MemTotal" | grep -Eo "[0-9]+")
RAM=$(($RAM / 1048576))
if [ "$RAM" -ge "3" ]; then
echo "RAM достаточно"
else
echo "Для управляющего/сетевого узла нужно как минимум 4 GB RAM"
exit 1
fi
}

function setup_steps() {
node_init_config

case $NODE_TYPE in
    "1")
      setup_steps_controll_node
      ;;
    "2")
      setup_steps_compute_node
      ;;
    "3")
      setup_steps_network_node
      ;;
    "4")
      setup_steps_storage_node
      ;;
    "5")
      setup_steps_nfs_server
      ;;
    *)
      exit 0
      ;;
esac
}

function setup_steps_controll_node() {
if [[ "${service_menu[3]}" == "1" ]]; then
mariadb_config
fi
if [[ "${service_menu[1]}" == "1" ]]; then
rabbitmq_config
fi
if [[ "${service_menu[5]}" == "1" ]]; then
nginx_config
fi
if [[ "${service_menu[7]}" == "1" ]]; then
memcached_config
keystone_config
fi
if [[ "${service_menu[9]}" == "1" ]]; then
glance_config
fi
if [[ "${service_menu[11]}" == "1" ]]; then
nova_controller_config
fi
if [[ "${service_menu[13]}" == "1" ]]; then
neutron_controller_config
fi
if [[ "${service_menu[15]}" == "1" ]]; then
cinder_controller_config
fi
if [[ "${service_menu[17]}" == "1" ]]; then
horizon_config
fi
if [[ "${service_menu[19]}" == "1" ]]; then
telemetry_controller_config
fi
if [[ "${service_menu[21]}" == "1" ]]; then
heat_controller_config
fi
if [[ "${service_menu[23]}" == "1" ]]; then
barbican_config
fi
if [[ "${service_menu[25]}" == "1" ]]; then
manila_controller_config
fi
if [[ "${service_menu[27]}" == "1" ]]; then
designate_controller_config
fi
if [[ "${service_menu[29]}" == "1" ]]; then
octavia_controller_config
fi
if [[ "${service_menu[31]}" == "1" ]]; then
magnum_controller_config
fi
if [[ "${service_menu[33]}" == "1" ]]; then
rally_config
fi
if [[ "${service_menu[35]}" == "1" ]]; then
kitty_controller_config
fi
}


function setup_steps_compute_node() {
if [[ "${service_menu[11]}" == "1" ]]; then
nova_compute_config
fi
if [[ "${service_menu[13]}" == "1" ]]; then
neutron_compute_config
fi
if [[ "${service_menu[15]}" == "1" ]]; then
cinder_compute_config
fi
if [[ "${service_menu[19]}" == "1" ]]; then
telemetry_compute_config
fi
}


function setup_steps_network_node() {
if [[ "${service_menu[13]}" == "1" ]]; then
neutron_network_config
fi
if [[ "${service_menu[19]}" == "1" ]]; then
telemetry_network_config
fi
if [[ "${service_menu[21]}" == "1" ]]; then
heat_network_config
fi
if [[ "${service_menu[27]}" == "1" ]]; then
desigante_network_config
fi
if [[ "${service_menu[29]}" == "1" ]]; then
octavia_network_config
fi
if [[ "${service_menu[31]}" == "1" ]]; then
magnum_network_config
fi
if [[ "${service_menu[35]}" == "1" ]]; then
kitty_network_config
fi
}


function setup_steps_storage_node() {
if [[ "${service_menu[15]}" == "1" ]]; then
cinder_storage_config
fi
if [[ "${service_menu[25]}" == "1" ]]; then
manila_storage_config
fi
}


function setup_steps_nfs_server() {
if [[ "${service_menu[15]}" == "1" ]]; then
nfs_storage_config
fi
}


function check() {
echo "RABBIT_PASS=$RABBIT_PASS"
echo "KEYSTONE_PASS=$KEYSTONE_PASS"
echo "ADMIN_PASS=$ADMIN_PASS"
echo "GLANCE_PASS=$GLANCE_PASS"
echo "NEUTRON_PASS=$NEUTRON_PASS"
echo "NOVA_HOSTNAME=$NOVA_HOSTNAME"
echo "NOVA_PASS=$NOVA_PASS"
echo "PLACEMENT_PASS=$PLACEMENT_PASS"
echo "METADATA_SECRET=$METADATA_SECRET"
echo "DB_PASS=$DB_PASS"
echo "CINDER_PASS=$CINDER_PASS"
echo "NOVA_IP=$NOVA_IP"
echo "HOST_IP=$HOST_IP"
echo "NFS_HOSTNAME=$NFS_HOSTNAME"
echo "TIME_ZONE=$TIME_ZONE"
echo "GNOCCHI_PASS=$GNOCCHI_PASS"
echo "GNOCCHI_HOSTNAME=$GNOCCHI_HOSTNAME"
echo "CEILOMETER_PASS=$CEILOMETER_PASS"
echo "AODH_PASS=$AODH_PASS"
echo "AODH_HOSTNAME=$AODH_HOSTNAME"
echo "HEAT_PASS=$HEAT_PASS"
echo "HEAT_HOSTNAME=$HEAT_HOSTNAME"
echo "BARBICAN_PASS=$BARBICAN_PASS"
echo "MANILA_PASS=$MANILA_PASS"
echo "DESIGNATE_PASS=$DESIGNATE_PASS"
echo "DESIGNATE_HOSTNAME=$DESIGNATE_HOSTNAME"
echo "OCTAVIA_PASS=$OCTAVIA_PASS"
echo "OCTAVIA_HOSTNAME=$OCTAVIA_HOSTNAME"
echo "MAGNUM_PASS=$MAGNUM_PASS"
echo "MAGNUM_HOSTNAME=$MAGNUM_HOSTNAME"
echo "RALLY_PASS=$RALLY_PASS"
echo "KITTY_PASS=$KITTY_PASS"
echo "KITTY_HOSTNAME=$KITTY_HOSTNAME"
echo "DNS=$DNS"
echo "HOSTNAME=$HOSTNAME"
echo "HOST_NETWORK=$HOST_NETWORK"
echo "NEUTRON_IP=$NEUTRON_IP"
}

display_menu
