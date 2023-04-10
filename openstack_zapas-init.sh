#!/bin/bash

NODE_TYPE="1"

HOST_IP=""
HOST_NETWORK=""
DNS=""

NOVA_IP="192.168.122.20"
NEUTRON_IP="192.168.122.22"
NEUTRON_PASS="neutron"
ADMIN_PASS="openstack"
DB_PASS="mariadb"
RABBIT_PASS="rabbit"
GLANCE_PASS="glance"
KEYSTONE_PASS="keystone"
CINDER_PASS="cinder"
AODH_PASS="aodh"
GNOCCHI_PASS="gnocchi"
HEAT_PASS="heat"
NOVA_PASS="nova"
PLACEMENT_PASS="placement"
CEILOMETER_PASS="ceilometer"
BARBICAN_PASS="barbican"
MANILA_PASS="manila"
DESIGNATE_PASS="designate"
OCTAVIA_PASS="octavia"
MAGNUM_PASS="magnum"
RALLY_PASS="rally"
KITTY_PASS="cloudkitty"
TROVE_PASS="trove"
METADATA_SECRET="openstack"
TIME_ZONE=""
GNOCCHI_HOSTNAME="network.test.local"
NFS_HOSTNAME="network.test.local"
HOSTNAME="controller.test.local"
NOVA_HOSTNAME="controller.test.local"
AODH_HOSTNAME="network.test.local"
HEAT_HOSTNAME="network.test.local"
DESIGNATE_HOSTNAME="network.test.local"
OCTAVIA_HOSTNAME="network.test.local"
MAGNUM_HOSTNAME="network.test.local"
KITTY_HOSTNAME="network.test.local"
TROVE_HOSTNAME="network.test.local"




function node_init_config() {

echo "Установка Openstack Zed на Centos Stream 9"

echo -e "\033[1mПОДГОТОВКА УЗЛА\033[0m"

echo "Изменение имени узла"

hostnamectl set-hostname $HOSTNAME

echo "Добавление имен и ip-адресов других узлов в файл /etc/hosts"

echo "$HOST_IP $HOSTNAME" >> /etc/hosts
answer="y"
while [ "$answer" != "n" ]; do 
read -p "Хотите ввести параметры другого узла для удобного к нему обращения? (y|n)" answer
if [ "$answer" == "y" ]; then
read -p "Введите ip-адрес: " ip
read -p "Введите имя узла: " name
echo "$ip $name" >> /etc/hosts
fi
done

echo "Установка chrony"

dnf -y install chrony

echo "Редактирование конфига /etc/chrony.conf"

sed -c -i 's/pool 2.centos.pool.ntp.org iburst/pool 0.pool.ntp.org iburst/' /etc/chrony.conf
sed -c -i 's/#allow 192.168.0.0\/16/allow '$HOST_NETWORK'\/24/' /etc/chrony.conf

echo "Добавление Chrony в исключения firewall"

firewall-cmd --add-service=ntp
firewall-cmd --runtime-to-permanent

echo "Перезапуск chronyd"

systemctl restart chronyd
systemctl enable --now chronyd

echo "Добавление репозитория Openstack Zed"

dnf -y install centos-release-openstack-zed
sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/CentOS-OpenStack-zed.repo

echo "Добавление репозитория EPEL"

dnf -y install epel-release epel-next-release
sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/epel.repo
sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/epel-next.repo

echo "Обновление системы CentOS"

dnf --enablerepo=centos-openstack-zed -y upgrade

echo "Установка Crudini"

dnf --enablerepo=epel,epel-next -y install crudini
}



function mariadb_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА MariaDB\033[0m"

echo "Установка mariadb-server"

dnf -y install mariadb-server

echo "Редактирование конфига /etc/my.cnf.d/charset.cnf"

{
echo "[mysqld]"
echo "character-set-server = utf8mb4"
echo "[client]"
echo "default-character-set = utf8mb4"
} > /etc/my.cnf.d/charset.cnf

echo "Добавление Chrony в исключения firewall"

firewall-cmd --add-service=mysql 
firewall-cmd --runtime-to-permanent 

echo "Запуск mariadb"

systemctl enable --now mariadb

echo "Запуск скрипта mysql_secure_installation"

mysql_secure_installation << EOF

y
y
$DB_PASS
$DB_PASS
y
y
y
y
EOF

echo "Изменение пароля root для MySQL"

mysql --user="root" --execute="ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_PASS';"
}



function rabbitmq_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА RabbitMQ\033[0m"

echo "Установка rabbitmq-server"

dnf -y install rabbitmq-server

echo "Редактирование конфига /etc/my.cnf.d/mariadb-server.cnf"

crudini --ini-options=nospace --set /etc/my.cnf.d/mariadb-server.cnf mysqld max_connections 1024

echo "Создание конфига /etc/rabbitmq/rabbitmq-env.conf"

touch /etc/rabbitmq/rabbitmq-env.conf
{
echo "RABBITMQ_NODENAME=rabbit@$NOVA_HOSTNAME"
echo "RABBITMQ_USE_LONGNAME=true"
} > /etc/rabbitmq/rabbitmq-env.conf
chown rabbitmq:rabbitmq /etc/rabbitmq/rabbitmq-env.conf

echo "Запуск rabbitmq-server"

systemctl enable --now rabbitmq-server

rabbitmqctl set_cluster_name rabbit@$NOVA_HOSTNAME

echo "Изменение пароля дефолтного пользователя (user) RabbitMQ"

rabbitmqctl change_password guest $RABBIT_PASS

echo "Изменение политик SELinux касательно RabbitMQ"

cat << EOF > rabbitmqctl.te
module rabbitmqctl 1.0;

require {
        type rabbitmq_t;
        type tmpfs_t;
        type init_var_run_t;
        type rabbitmq_t;
        class sock_file { getattr read };
        class file { execute map read write };
        class process execmem;
}

#============= rabbitmq_t ==============
allow rabbitmq_t self:process execmem;
allow rabbitmq_t tmpfs_t:file { execute read write };
allow rabbitmq_t tmpfs_t:file map;
allow rabbitmq_t init_var_run_t:sock_file { getattr read };
EOF
checkmodule -m -M -o rabbitmqctl.mod rabbitmqctl.te
semodule_package --outfile rabbitmqctl.pp --module rabbitmqctl.mod
semodule -i rabbitmqctl.pp

echo "Добавление RabbitMQ в исключения firewall"

firewall-cmd --add-port=5672/tcp
firewall-cmd --runtime-to-permanent 
}




function memcached_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Memcached\033[0m"

echo "Установка memcached"

dnf -y install memcached

echo "Редактирование конфига /etc/sysconfig/memcached"

crudini --ini-options=nospace --set /etc/sysconfig/memcached "" OPTIONS "\"-l 0.0.0.0,::\""

echo "Запуск memcached"

systemctl enable --now memcached

echo "Добавление Memcached в исключения firewall"

firewall-cmd --add-service=memcache	
firewall-cmd --runtime-to-permanent
}




function keystone_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Keystone\033[0m"

echo "Создание БД для сервиса Keystone"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE keystone;"

echo "Выдача прав на работу с БД пользователю keystone"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Установка служб необходимых для работы Keystone"

dnf --enablerepo=centos-openstack-zed,epel -y install openstack-keystone python3-openstackclient httpd python3-mod_wsgi

echo "Редактирование конфига /etc/keystone/keystone.conf"

crudini --set /etc/keystone/keystone.conf cache memcache_servers $NOVA_HOSTNAME:11211
crudini --set /etc/keystone/keystone.conf database connection mysql+pymysql://keystone:$KEYSTONE_PASS@$NOVA_HOSTNAME/keystone
crudini --set /etc/keystone/keystone.conf token provider fernet

echo "Инициализация БД keystone"

su -s /bin/bash keystone -c "keystone-manage db_sync" 
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

echo "Инициализация сервиса Keystone с помощью keystone-manage bootstrap"

keystone-manage bootstrap --bootstrap-password $ADMIN_PASS --bootstrap-admin-url http://$NOVA_HOSTNAME:5000/v3/ --bootstrap-internal-url http://$NOVA_HOSTNAME:5000/v3/ --bootstrap-public-url http://$NOVA_HOSTNAME:5000/v3/ --bootstrap-region-id RegionOne

echo "Редактирование конфига /etc/httpd/conf/httpd.conf"

echo "ServerName $NOVA_HOSTNAME" >> /etc/httpd/conf/httpd.conf

echo "Создание файла /etc/httpd/conf.d//wsgi-keystone.conf"

ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/

echo "Изменение политик SELinux касательно Httpd/Keystone"

setsebool -P httpd_use_openstack on
setsebool -P httpd_can_network_connect on
setsebool -P httpd_can_network_connect_db on
cat << EOF > keystone-httpd.te
module keystone-httpd 1.0;

require {
        type httpd_t;
        type keystone_var_lib_t;
        type keystone_log_t;
        class file { create getattr ioctl open read write };
        class dir { add_name create write };
}

#============= httpd_t ==============
allow httpd_t keystone_var_lib_t:dir { add_name create write };
allow httpd_t keystone_var_lib_t:file { create open write getattr ioctl open read };
allow httpd_t keystone_log_t:dir { add_name write };
allow httpd_t keystone_log_t:file create;
EOF
checkmodule -m -M -o keystone-httpd.mod keystone-httpd.te
semodule_package --outfile keystone-httpd.pp --module keystone-httpd.mod
semodule -i keystone-httpd.pp

echo "Добавление Keystone в исключения firewall"

firewall-cmd --add-port=5000/tcp
firewall-cmd --runtime-to-permanent

echo "Запуск httpd(keystone)"

systemctl enable --now httpd

echo "Создание скрипта для удобной работы с сервисом Keystone от имени администратора"

{
echo "unset OS_USERNAME OS_PASSWORD OS_PROJECT_NAME OS_USER_DOMAIN_NAME OS_PROJECT_DOMAIN_NAME OS_AUTH_URL OS_IDENTITY_API_VERSION PS1 REQUESTS_CA_BUNDLE"
echo "export OS_USERNAME=admin"
echo "export OS_PASSWORD=$ADMIN_PASS"
echo "export OS_PROJECT_NAME=admin"
echo "export OS_USER_DOMAIN_NAME=default"
echo "export OS_PROJECT_DOMAIN_NAME=default"
echo "export OS_AUTH_URL=http://$NOVA_HOSTNAME:5000"
echo "export OS_IDENTITY_API_VERSION=3"
echo "export OS_IMAGE_API_VERSION=2"
echo "export OS_VOLUME_API_VERSION=3"
echo "export PS1='[\u@\h \W(Openstack_Admin)]\$ '"
} > ~/keystonerc_adm
source ~/keystonerc_adm

echo "Создание проекта service для регистрации будущих сервисов"

openstack project create --domain default --description "Service Project" service
}



function glance_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Glance\033[0m"

echo "Создание пользователя glance"

source ~/keystonerc_adm
openstack user create --domain default --project service --password $GLANCE_PASS glance 

echo "Присваивание пользователю glance роли admin в проекте serivce"

openstack role add --project service --user glance admin

echo "Создание сервиса glance"

openstack service create --name glance --description "Image Service" image

echo "Создание точек входа в сервис glance"

openstack endpoint create --region RegionOne image public http://$NOVA_HOSTNAME:9292
openstack endpoint create --region RegionOne image internal http://$NOVA_HOSTNAME:9292
openstack endpoint create --region RegionOne image admin http://$NOVA_HOSTNAME:9292

echo "Создание БД для сервиса Glance"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE glance;"

echo "Выдача прав на работу с БД пользователю glance"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя glance в RabbitMQ"

rabbitmqctl add_user glance $GLANCE_PASS

echo "Выдача созданному RabbitMQ пользователю всех разрешений"

rabbitmqctl set_permissions glance ".*" ".*" ".*"

echo "Установка служб необходимых для работы сервиса Glance"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-glance

echo "Редактирование конфига /etc/glance/glance-api.conf"

crudini --set /etc/glance/glance-api.conf DEFAULT transport_url rabbit://glance:$GLANCE_PASS@$NOVA_HOSTNAME
crudini --set /etc/glance/glance-api.conf DEFAULT log_dir /var/log/glance
crudini --set /etc/glance/glance-api.conf glance_store stores file,http
crudini --set /etc/glance/glance-api.conf glance_store default_store file
crudini --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir /var/lib/glance/images/
crudini --set /etc/glance/glance-api.conf database connection mysql+pymysql://glance:$GLANCE_PASS@$NOVA_HOSTNAME/glance
crudini --set /etc/glance/glance-api.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/glance/glance-api.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_type password
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_domain_name default
crudini --set /etc/glance/glance-api.conf keystone_authtoken user_domain_name default
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_name service
crudini --set /etc/glance/glance-api.conf keystone_authtoken username glance
crudini --set /etc/glance/glance-api.conf keystone_authtoken password $GLANCE_PASS
crudini --set /etc/glance/glance-api.conf paste_deploy flavor keystone

echo "Инициализация БД glance"

su -s /bin/bash glance -c "glance-manage db_sync"

echo "Изменение политик SELinux касательно Glance"

setsebool -P glance_api_can_network on
cat << EOF > glanceapi.te 
module glanceapi 1.0;

require {
        type glance_api_t;
        type mysqld_exec_t;
        type mysqld_safe_exec_t;
        type rpm_exec_t;
        type hostname_exec_t;
        type sudo_exec_t;
        type httpd_config_t;
        type iscsid_exec_t;
        type gpg_exec_t;
        type crontab_exec_t;
        type consolehelper_exec_t;
        type glance_port_t;
        type keepalived_exec_t;
        type httpd_t;
        class tcp_socket name_bind;
        class dir search;
        class file { getattr open read };
}

#============= glance_api_t ==============
allow glance_api_t httpd_config_t:dir search;
allow glance_api_t mysqld_exec_t:file getattr;
allow glance_api_t mysqld_safe_exec_t:file getattr;
allow glance_api_t gpg_exec_t:file getattr;
allow glance_api_t hostname_exec_t:file getattr;
allow glance_api_t rpm_exec_t:file getattr;
allow glance_api_t sudo_exec_t:file getattr;
allow glance_api_t consolehelper_exec_t:file getattr;
allow glance_api_t crontab_exec_t:file getattr;
allow glance_api_t iscsid_exec_t:file { getattr open read };
allow glance_api_t keepalived_exec_t:file getattr;

#============= httpd_t ==============
allow httpd_t glance_port_t:tcp_socket name_bind;
EOF
checkmodule -m -M -o glanceapi.mod glanceapi.te
semodule_package --outfile glanceapi.pp --module glanceapi.mod 
semodule -i glanceapi.pp

echo "Добавление Glance в исключения firewall"

firewall-cmd --add-port=9292/tcp
firewall-cmd --runtime-to-permanent 

echo "Запуск openstack-glance-api"

systemctl enable --now openstack-glance-api
}




function cinder_controller_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Cinder\033[0m"

echo "Создание пользователя cinder"

source ~/keystonerc_adm
openstack user create --domain default --project service --password $CINDER_PASS cinder

echo "Присваивание пользователю cinder роли admin в проекте serivce"

openstack role add --project service --user cinder admin 

echo "Создание сервиса cinder"

openstack service create --name cinderv3 --description "Block Storage" volumev3

echo "Создание точек входа в сервисы cinder"

openstack endpoint create --region RegionOne volumev3 public http://$NOVA_HOSTNAME:8776/v3
openstack endpoint create --region RegionOne volumev3 internal http://$NOVA_HOSTNAME:8776/v3
openstack endpoint create --region RegionOne volumev3 admin http://$NOVA_HOSTNAME:8776/v3

echo "Создание БД для сервиса Cinder"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE cinder;"

echo "Выдача прав на работу с БД пользователю cinder"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$CINDER_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя cinder в RabbitMQ"

rabbitmqctl add_user cinder $CINDER_PASS

echo "Выдача созданному RabbitMQ пользователю всех разрешений"

rabbitmqctl set_permissions cinder ".*" ".*" ".*"

echo "Установка служб необходимых для работы сервиса Cinder"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-cinder

echo "Редактирование конфига /etc/cinder/cinder.conf"

crudini --set /etc/cinder/cinder.conf DEFAULT rootwrap_config /etc/cinder/rootwrap.conf
crudini --set /etc/cinder/cinder.conf DEFAULT api_paste_confg /etc/cinder/api-paste.ini
crudini --set /etc/cinder/cinder.conf DEFAULT enable_v3_api true
crudini --set /etc/cinder/cinder.conf DEFAULT transport_url rabbit://cinder:$CINDER_PASS@$NOVA_HOSTNAME
crudini --set /etc/cinder/cinder.conf DEFAULT state_path /var/lib/cinder
crudini --set /etc/cinder/cinder.conf DEFAULT auth_strategy keystone
crudini --set /etc/cinder/cinder.conf database connection mysql+pymysql://cinder:$CINDER_PASS@$NOVA_HOSTNAME/cinder
crudini --set /etc/cinder/cinder.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/cinder/cinder.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_type password
crudini --set /etc/cinder/cinder.conf keystone_authtoken project_domain_name default
crudini --set /etc/cinder/cinder.conf keystone_authtoken user_domain_name default
crudini --set /etc/cinder/cinder.conf keystone_authtoken project_name service
crudini --set /etc/cinder/cinder.conf keystone_authtoken username cinder
crudini --set /etc/cinder/cinder.conf keystone_authtoken password $CINDER_PASS
crudini --set /etc/cinder/cinder.conf oslo_concurrency lock_path /var/lib/cinder/tmp

echo "Инициализация БД cinder"

su -s /bin/bash cinder -c "cinder-manage db sync"

echo "Установка openstack-selinux"

dnf --enablerepo=centos-openstack-zed -y install openstack-selinux

echo "Изменение политик SELinux касательно Cinder"

semanage port -a -t http_port_t -p tcp 8776

echo "Добавление Cinder в исключения firewall"

firewall-cmd --add-port=8776/tcp
firewall-cmd --runtime-to-permanent

echo "Запуск openstack-cinder-api, openstack-cinder-scheduler, openstack-cinder-volume и openstack-cinder-backup"

systemctl enable --now openstack-cinder-api
systemctl enable --now openstack-cinder-scheduler
}



function cinder_storage_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Cinder\033[0m"

echo "Установка служб необходимых для работы сервиса Cinder"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-cinder

echo "Установка targetcli"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install targetcli

echo "Редактирование конфига /etc/cinder/cinder.conf"

crudini --set /etc/cinder/cinder.conf DEFAULT my_ip $HOST_IP
crudini --set /etc/cinder/cinder.conf DEFAULT rootwrap_config /etc/cinder/rootwrap.conf
crudini --set /etc/cinder/cinder.conf DEFAULT api_paste_confg /etc/cinder/api-paste.ini
crudini --set /etc/cinder/cinder.conf DEFAULT auth_strategy keystone
crudini --set /etc/cinder/cinder.conf DEFAULT transport_url rabbit://cinder:$CINDER_PASS@$NOVA_HOSTNAME
crudini --set /etc/cinder/cinder.conf DEFAULT enable_v3_api true
crudini --set /etc/cinder/cinder.conf DEFAULT glance_api_servers http://$NOVA_HOSTNAME:9292
crudini --set /etc/cinder/cinder.conf DEFAULT enabled_backends lvm
crudini --set /etc/cinder/cinder.conf DEFAULT backup_driver cinder.backup.drivers.nfs.NFSBackupDriver
crudini --set /etc/cinder/cinder.conf DEFAULT backup_mount_point_base /var/lib/cinder/backup_nfs
crudini --set /etc/cinder/cinder.conf DEFAULT backup_share $NFS_HOSTNAME:/backup/nfs
crudini --set /etc/cinder/cinder.conf DEFAULT state_path /var/lib/cinder
crudini --set /etc/cinder/cinder.conf lvm target_helper lioadm
crudini --set /etc/cinder/cinder.conf lvm target_protocol iscsi
crudini --set /etc/cinder/cinder.conf lvm target_ip_address $HOST_IP
crudini --set /etc/cinder/cinder.conf lvm volume_group cinder-volumes
crudini --set /etc/cinder/cinder.conf lvm volume_driver cinder.volume.drivers.lvm.LVMVolumeDriver
crudini --set /etc/cinder/cinder.conf lvm volumes_dir /var/lib/cinder/volumes
crudini --set /etc/cinder/cinder.conf database connection mysql+pymysql://cinder:$CINDER_PASS@$NOVA_HOSTNAME/cinder
crudini --set /etc/cinder/cinder.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/cinder/cinder.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_type password
crudini --set /etc/cinder/cinder.conf keystone_authtoken project_domain_name default
crudini --set /etc/cinder/cinder.conf keystone_authtoken user_domain_name default
crudini --set /etc/cinder/cinder.conf keystone_authtoken project_name service
crudini --set /etc/cinder/cinder.conf keystone_authtoken username cinder
crudini --set /etc/cinder/cinder.conf keystone_authtoken password $CINDER_PASS
crudini --set /etc/cinder/cinder.conf oslo_concurrency lock_path /var/lib/cinder/tmp

echo "Изменение политик SELinux касательно Cinder"

cat << EOF > iscsiadm.te
module iscsiadm 1.0;

require {
        type iscsid_t;
        type lsmd_plugin_exec_t;
        type systemd_notify_exec_t;
        type rsync_exec_t;
        type thumb_exec_t;
        type ssh_agent_exec_t;
        type checkpolicy_exec_t;
        type crontab_exec_t;
        type locate_exec_t;
        type conmon_exec_t;
        type NetworkManager_exec_t;
        type dmesg_exec_t;
        type mount_exec_t;
        type traceroute_exec_t;
        type neutron_t;
        type vlock_exec_t;
        type fusermount_exec_t;
        type login_exec_t;
        type su_exec_t;
        type cinder_backup_exec_t;
        type loadkeys_exec_t;
        type groupadd_exec_t;
        type systemd_hwdb_exec_t;
        type mandb_exec_t;
        type policykit_auth_exec_t;
        type hostname_exec_t;
        type passwd_exec_t;
        type systemd_passwd_agent_exec_t;
        type dbusd_exec_t;
        type virtd_exec_t;
        type cinder_volume_exec_t;
        type chronyc_exec_t;
        type systemd_systemctl_exec_t;
        type journalctl_exec_t;
        type ping_exec_t;
        type ssh_exec_t;
        type plymouth_exec_t;
        type gpg_exec_t;
        type devicekit_exec_t;
        type chfn_exec_t;
        type cinder_api_exec_t;
        type gpg_agent_exec_t;
        type kdumpctl_exec_t;
        type cinder_scheduler_exec_t;
        type ssh_keygen_exec_t;
        type systemd_tmpfiles_exec_t;
        type rpcbind_exec_t;
        type rpmdb_exec_t;
        type keepalived_exec_t;
        type virt_qemu_ga_exec_t;
        type container_runtime_exec_t;
        type lsmd_exec_t;
        class file getattr;
        class capability dac_override;
}

#============= iscsid_t ==============
allow iscsid_t self:capability dac_override;

#============= neutron_t ==============
allow neutron_t cinder_api_exec_t:file getattr;
allow neutron_t cinder_backup_exec_t:file getattr;
allow neutron_t cinder_scheduler_exec_t:file getattr;
allow neutron_t cinder_volume_exec_t:file getattr;
allow neutron_t rpcbind_exec_t:file getattr;
allow neutron_t virtd_exec_t:file getattr;
EOF
checkmodule -m -M -o iscsiadm.mod iscsiadm.te
semodule_package --outfile iscsiadm.pp --module iscsiadm.mod
semodule -i iscsiadm.pp

echo "Добавление Cinder в исключения firewall"

firewall-cmd --add-service=iscsi-target
firewall-cmd --runtime-to-permanent

echo "Создание lvm-группы cinder-volumes на отельном диске"

vgcreate cinder-volumes /dev/vdb

echo "Установка и запуск nfs-utils"

dnf -y install nfs-utils 
systemctl enable --now nfs-server

echo "Редактирование конфига /etc/idmapd.conf"

sed -c -i 's/#Domain = local.domain.edu/Domain = '$DNS'/' /etc/idmapd.conf

echo "Добавление NFS в исключения firewall"

firewall-cmd --add-service=nfs
firewall-cmd --runtime-to-permanent

echo "Запуск iscsid и target"

systemctl enable --now iscsid
systemctl enable --now target

echo "Запуск openstack-cinder-volume и openstack-cinder-backup"

systemctl enable --now openstack-cinder-volume
systemctl enable --now openstack-cinder-backup
chown -R cinder. /var/lib/cinder/backup_nfs
}




function nfs_storage_config() {

echo -e "\033[1mНАСТРОЙКА NFS-СЕРВЕРА\033[0m"

echo "Редактирование конфига /etc/idmapd.conf"

sed -c -i 's/#Domain = local.domain.edu/Domain = '$DNS'/' /etc/idmapd.conf

echo "Экспорт папки /backup/nfs для бэкапов"

mkdir -p /backup/nfs
chmod 777 /backup/nfs
echo "/backup/nfs $HOST_NETWORK/24(rw,sync,no_root_squash,no_all_squash)" >> /etc/exports
exportfs -a

echo "Добавление NFS в исключения firewall"

firewall-cmd --add-service=nfs
firewall-cmd --add-service={nfs3,mountd,rpc-bind}
firewall-cmd --runtime-to-permanent

echo "Запуск nfs-server и rpcbind"

systemctl enable --now nfs-server rpcbind
}



function cinder_compute_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Cinder\033[0m"

echo "Редактирование конфига /etc/nova/nova.conf"

crudini --set /etc/nova/nova.conf cinder os_region_name RegionOne

echo "Перезапуск openstack-nova-compute"

systemctl restart openstack-nova-compute 

echo "Изменение политик SELinux касательно Cinder"

cat << EOF > iscsiadm.te
module iscsiadm 1.0;

require {
        type iscsid_t;
        class capability dac_override;
}

#============= iscsid_t ==============
allow iscsid_t self:capability dac_override;
EOF
checkmodule -m -M -o iscsiadm.mod iscsiadm.te
semodule_package --outfile iscsiadm.pp --module iscsiadm.mod
semodule -i iscsiadm.pp

echo "Запуск сервиса iscsid"

systemctl enable --now iscsid
}


function nova_controller_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Nova И Placement\033[0m"

echo "Создание пользователя nova"

source ~/keystonerc_adm
openstack user create --domain default --project service --password $NOVA_PASS nova

echo "Присваивание пользователю nova роли admin в проекте serivce"

openstack role add --project service --user nova admin 

echo "Создание пользователя placement"

openstack user create --domain default --project service --password $PLACEMENT_PASS placement

echo "Присваивание пользователю placement роли admin в проекте serivce"

openstack role add --project service --user placement admin 

echo "Создание сервиса nova"

openstack service create --name nova --description "Compute Service" compute

echo "Создание сервиса placement"

openstack service create --name placement --description "Compute Placement Service" placement

echo "Создание точек входа в сервиса nova"

openstack endpoint create --region RegionOne compute public http://$NOVA_HOSTNAME:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://$NOVA_HOSTNAME:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://$NOVA_HOSTNAME:8774/v2.1

echo "Создание точек входа в сервиса placement"

openstack endpoint create --region RegionOne placement public http://$NOVA_HOSTNAME:8778
openstack endpoint create --region RegionOne placement internal http://$NOVA_HOSTNAME:8778
openstack endpoint create --region RegionOne placement admin http://$NOVA_HOSTNAME:8778

echo "Создание трех БД (nova, nova_api и nova_cell0)для сервиса Nova"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE nova_api;"
mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE nova;"
mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE nova_cell0;"

echo "Выдача прав на работу с БД пользователю nova"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание БД для сервиса Placement"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE placement;"

echo "Выдача прав на работу с БД пользователю placement"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PLACEMENT_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PLACEMENT_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя nova в RabbitMQ"

rabbitmqctl add_user nova $NOVA_PASS

echo "Выдача созданному RabbitMQ пользователю всех разрешений"

rabbitmqctl set_permissions nova ".*" ".*" ".*"

echo "Установка служб необходимых для работы сервиса Nova и Placement"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-nova openstack-placement-api 

echo "Редактирование конфига /etc/nova/nova.conf"

crudini --set /etc/nova/nova.conf DEFAULT my_ip $HOST_IP
crudini --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
crudini --set /etc/nova/nova.conf DEFAULT transport_url rabbit://nova:$NOVA_PASS@$NOVA_HOSTNAME
crudini --set /etc/nova/nova.conf DEFAULT log_dir /var/log/nova
crudini --set /etc/nova/nova.conf DEFAULT state_path /var/lib/nova
crudini --set /etc/nova/nova.conf DEFAULT instances_path /var/lib/nova/instances
crudini --set /etc/nova/nova.conf api auth_strategy keystone
crudini --set /etc/nova/nova.conf vnc enabled true
crudini --set /etc/nova/nova.conf vnc server_listen $HOST_IP
crudini --set /etc/nova/nova.conf vnc server_proxyclient_address $HOST_IP
crudini --set /etc/nova/nova.conf glance api_servers http://$NOVA_HOSTNAME:9292
crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp
crudini --set /etc/nova/nova.conf api_database connection mysql+pymysql://nova:$NOVA_PASS@$NOVA_HOSTNAME/nova_api
crudini --set /etc/nova/nova.conf database connection mysql+pymysql://nova:$NOVA_PASS@$NOVA_HOSTNAME/nova
crudini --set /etc/nova/nova.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name default
crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name default
crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
crudini --set /etc/nova/nova.conf keystone_authtoken username nova
crudini --set /etc/nova/nova.conf keystone_authtoken password $NOVA_PASS
crudini --set /etc/nova/nova.conf placement auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/nova/nova.conf placement region_name RegionOne
crudini --set /etc/nova/nova.conf placement auth_type password
crudini --set /etc/nova/nova.conf placement project_domain_name default
crudini --set /etc/nova/nova.conf placement user_domain_name default
crudini --set /etc/nova/nova.conf placement project_name service
crudini --set /etc/nova/nova.conf placement username placement
crudini --set /etc/nova/nova.conf placement password $PLACEMENT_PASS
crudini --set /etc/nova/nova.conf wsgi api_paste_config /etc/nova/api-paste.ini

echo "Редактирование конфига /etc/placement/placement.conf"

crudini --set /etc/placement/placement.conf DEFAULT debug false 
crudini --set /etc/placement/placement.conf api auth_strategy keystone
crudini --set /etc/placement/placement.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/placement/placement.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/placement/placement.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/placement/placement.conf keystone_authtoken auth_type password
crudini --set /etc/placement/placement.conf keystone_authtoken project_domain_name default
crudini --set /etc/placement/placement.conf keystone_authtoken user_domain_name default
crudini --set /etc/placement/placement.conf keystone_authtoken project_name service
crudini --set /etc/placement/placement.conf keystone_authtoken username placement
crudini --set /etc/placement/placement.conf keystone_authtoken password $PLACEMENT_PASS
crudini --set /etc/placement/placement.conf placement_database connection mysql+pymysql://placement:$PLACEMENT_PASS@$NOVA_HOSTNAME/placement

echo "Редактирование кофига /etc/httpd/conf.d/00-placement-api.conf"

sed -i -c '/\/VirtualHost/i \
  <Directory /usr/bin>\
    Require all granted\
  </Directory>' /etc/httpd/conf.d/00-placement-api.conf 
  
echo "Выдача прав на папку с логами сервису Placement"

chown placement. /var/log/placement/
  
echo "Инициализация БД placement"

su -s /bin/bash placement -c "placement-manage db sync" 

echo "Инициализация БД nova_api"

su -s /bin/bash nova -c "nova-manage api_db sync" 

echo "Регистрация БД nova-cell0 в БД nova_api"

su -s /bin/bash nova -c "nova-manage cell_v2 map_cell0"

echo "Инициализация БД nova"

su -s /bin/bash nova -c "nova-manage db sync"

echo "Создание ячейки cell1 в БД nova_api"

su -s /bin/bash nova -c "nova-manage cell_v2 create_cell --name cell1"

echo "Уствновка openstack-selinux"

dnf --enablerepo=centos-openstack-zed -y install openstack-selinux

echo "Изменение политик SELinux касательно Placement"

semanage port -a -t http_port_t -p tcp 8778

echo "Изменение политик SELinux касательно Nova"

cat << EOF > novaapi.te
module novaapi 1.0;

require {
        type rpm_exec_t;
        type hostname_exec_t;
        type nova_t;
        type nova_var_lib_t;
        type virtlogd_t;
        type geneve_port_t;
        type mysqld_exec_t;
        type mysqld_safe_exec_t;
        type gpg_exec_t;
        type crontab_exec_t;
        type consolehelper_exec_t;
        type keepalived_exec_t;
        class dir { add_name remove_name search write };
        class file { append create getattr open unlink };
        class capability dac_override;

}

#============= nova_t ==============
allow nova_t mysqld_exec_t:file getattr;
allow nova_t mysqld_safe_exec_t:file getattr;
allow nova_t gpg_exec_t:file getattr;
allow nova_t hostname_exec_t:file getattr;
allow nova_t rpm_exec_t:file getattr;
allow nova_t consolehelper_exec_t:file getattr;
allow nova_t crontab_exec_t:file getattr;
allow nova_t keepalived_exec_t:file getattr;

#============= virtlogd_t ==============
allow virtlogd_t nova_var_lib_t:dir { add_name remove_name search write };
allow virtlogd_t nova_var_lib_t:file { append create getattr open unlink };
allow virtlogd_t self:capability dac_override;
EOF
checkmodule -m -M -o novaapi.mod novaapi.te
semodule_package --outfile novaapi.pp --module novaapi.mod
semodule -i novaapi.pp

echo "Добавление Nova и Placement в исключения firewall"

firewall-cmd --add-port={6080/tcp,6081/tcp,6082/tcp,8774/tcp,8775/tcp,8778/tcp}
firewall-cmd --runtime-to-permanent

echo "Перезапуск httpd"

systemctl restart httpd

echo "Запуск openstack-nova-api openstack-nova-conductor openstack-nova-scheduler openstack-nova-novncproxy"

systemctl enable --now openstack-nova-api
systemctl enable --now openstack-nova-conductor
systemctl enable --now openstack-nova-scheduler
systemctl enable --now openstack-nova-novncproxy

echo "Регистрация гипервизоров рабочих узлов, если они есть"

su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova
}



function nova_compute_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Nova\033[0m"

echo "Установка служб необходимых для работы сервиса гипервизора KVM"

dnf -y install qemu-kvm libvirt virt-install

echo "Запуск libvirtd"

systemctl enable --now libvirtd

echo "установка службы openstack-nova-compute" 

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-nova-compute

echo "Редактирование конфига /etc/nova/nova.conf"

crudini --set /etc/nova/nova.conf DEFAULT my_ip $HOST_IP
crudini --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
crudini --set /etc/nova/nova.conf DEFAULT transport_url rabbit://nova:$NOVA_PASS@$NOVA_HOSTNAME
crudini --set /etc/nova/nova.conf DEFAULT log_dir /var/log/nova
crudini --set /etc/nova/nova.conf DEFAULT compute_driver libvirt.LibvirtDriver
crudini --set /etc/nova/nova.conf DEFAULT state_path /var/lib/nova
crudini --set /etc/nova/nova.conf api auth_strategy keystone
crudini --set /etc/nova/nova.conf vnc enabled true 
crudini --set /etc/nova/nova.conf vnc novncproxy_base_url http://$NOVA_HOSTNAME:6080/vnc_auto.html
crudini --set /etc/nova/nova.conf vnc server_listen 0.0.0.0
crudini --set /etc/nova/nova.conf vnc server_proxyclient_address $HOST_IP
crudini --set /etc/nova/nova.conf glance api_servers http://$NOVA_HOSTNAME:9292
crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp
crudini --set /etc/nova/nova.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name default
crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name default
crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
crudini --set /etc/nova/nova.conf keystone_authtoken username nova
crudini --set /etc/nova/nova.conf keystone_authtoken password $NOVA_PASS
crudini --set /etc/nova/nova.conf placement auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/nova/nova.conf placement region_name RegionOne
crudini --set /etc/nova/nova.conf placement auth_type password
crudini --set /etc/nova/nova.conf placement project_domain_name default
crudini --set /etc/nova/nova.conf placement user_domain_name default
crudini --set /etc/nova/nova.conf placement project_name service
crudini --set /etc/nova/nova.conf placement username placement
crudini --set /etc/nova/nova.conf placement password $PLACEMENT_PASS
crudini --set /etc/nova/nova.conf wsgi api_paste_config /etc/nova/api-paste.ini

echo "Установка openstack-selinux"

dnf --enablerepo=centos-openstack-zed -y install openstack-selinux

echo "Добавление Nova в исключения firewall"

firewall-cmd --add-port=5900-5999/tcp
firewall-cmd --runtime-to-permanent

echo "Запуск openstack-nova-compute"

systemctl enable --now openstack-nova-compute
}




function neutron_controller_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Neutron\033[0m"

echo "Создание пользователя neutron"

source ~/keystonerc_adm
openstack user create --domain default --project service --password $NEUTRON_PASS neutron

echo "Присваивание пользователю neutron роли admin в проекте serivce"

openstack role add --project service --user neutron admin 

echo "Создание сервиса neutron"

openstack service create --name neutron --description "Networking Service" network

echo "Создание точек входа в сервиса neutron"

openstack endpoint create --region RegionOne network public http://$NOVA_HOSTNAME:9696
openstack endpoint create --region RegionOne network internal http://$NOVA_HOSTNAME:9696
openstack endpoint create --region RegionOne network admin http://$NOVA_HOSTNAME:9696

echo "Создание БД для сервиса Neutron"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE neutron;"

echo "Выдача прав на работу с БД пользователю neutron"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя neutron в RabbitMQ"

rabbitmqctl add_user neutron $NEUTRON_PASS

echo "Выдача созданному RabbitMQ пользователю всех разрешений"

rabbitmqctl set_permissions neutron ".*" ".*" ".*"

echo "Редактирование конфига /etc/nova/nova.conf"

crudini --set /etc/nova/nova.conf neutron auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/nova/nova.conf neutron auth_type password
crudini --set /etc/nova/nova.conf neutron project_domain_name default
crudini --set /etc/nova/nova.conf neutron user_domain_name default
crudini --set /etc/nova/nova.conf neutron region_name RegionOne
crudini --set /etc/nova/nova.conf neutron project_name service
crudini --set /etc/nova/nova.conf neutron username neutron
crudini --set /etc/nova/nova.conf neutron password $NEUTRON_PASS
crudini --set /etc/nova/nova.conf neutron service_metadata_proxy true
crudini --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret $METADATA_SECRET

echo "Перезапуск openstack-nova-api"

systemctl restart openstack-nova-api
}






function neutron_network_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Neutron\033[0m"

echo "Установка служб необходимых для работы сервиса Neutron"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-neutron openstack-neutron-ml2 ovn-2021-central

echo "Редактирование конфига /etc/neutron/neutron.conf"

crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins ovn-router
crudini --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://neutron:$NEUTRON_PASS@$NOVA_HOSTNAME
crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips true
crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes true
crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes true
crudini --set /etc/neutron/neutron.conf DEFAULT state_path /var/lib/neutron
crudini --set /etc/neutron/neutron.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name default
crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name default
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
crudini --set /etc/neutron/neutron.conf keystone_authtoken password $NEUTRON_PASS
crudini --set /etc/neutron/neutron.conf database connection mysql+pymysql://neutron:$NEUTRON_PASS@$NOVA_HOSTNAME/neutron
crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp
crudini --set /etc/neutron/neutron.conf nova auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/neutron/neutron.conf nova auth_type password
crudini --set /etc/neutron/neutron.conf nova project_domain_name default
crudini --set /etc/neutron/neutron.conf nova user_domain_name default
crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
crudini --set /etc/neutron/neutron.conf nova project_name service
crudini --set /etc/neutron/neutron.conf nova username nova
crudini --set /etc/neutron/neutron.conf nova password $NOVA_PASS

echo "Редактирование конфига /etc/neutron/plugins/ml2/ml2_conf.ini"

crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat,geneve
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types geneve
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers ovn
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 overlay_ip_version 4
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks *
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_geneve vni_ranges 1:65536
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_geneve max_header_size 38
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group true
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_nb_connection tcp:$NEUTRON_IP:6641
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_sb_connection tcp:$NEUTRON_IP:6642
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_l3_scheduler leastloaded
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_metadata_enabled true

echo "Редактирование конфига /etc/sysconfig/openvswitch"

sed -c -i 's/OPTIONS=/"/"/OPTIONS=/"--ovsdb-server-options=/'--remote=ptcp:6640:127.0.0.1/'/"/' /etc/sysconfig/openvswitch

echo "Создание символической ссылки /etc/neutron/plugin.ini на файл /etc/neutron/plugins/ml2/ml2_conf.ini"

ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

echo "Инициализация БД neutron"

su -s /bin/bash neutron -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugin.ini upgrade head"

echo "Установка openstack-selinux"

dnf --enablerepo=centos-openstack-zed -y install openstack-selinux 

echo "Изменение политик SELinux касательно Neutron"

setsebool -P neutron_can_network on
setsebool -P haproxy_connect_any on 
setsebool -P daemons_enable_cluster_mode on
cat << EOF > ovsofctl.te
module ovsofctl 1.0;

require {
        type neutron_t;
        type neutron_exec_t;
        type dnsmasq_t;
        type tracefs_t;
        type openvswitch_load_module_t;
        type var_run_t;
        type openvswitch_t;
        type ovsdb_port_t;
        type dmesg_exec_t;
        type ping_exec_t;
        type ssh_exec_t;
        type ssh_keygen_exec_t;
        type crontab_exec_t;
        type dbusd_exec_t;
        type thumb_exec_t;
        type systemd_notify_exec_t;
        type keepalived_exec_t;
        type lsmd_plugin_exec_t;
        type gpg_agent_exec_t;
        type hostname_exec_t;
        type passwd_exec_t;
        type systemd_tmpfiles_exec_t;
        type rpmdb_exec_t;
        type systemd_hwdb_exec_t;
        type virt_qemu_ga_exec_t;
        type journalctl_exec_t;
        type conmon_exec_t;
        type locate_exec_t;
        type traceroute_exec_t;
        type mount_exec_t;
        type lsmd_exec_t;
        type policykit_auth_exec_t;
        type vlock_exec_t;
        type chronyc_exec_t;
        type ssh_agent_exec_t;
        type su_exec_t;
        type loadkeys_exec_t;
        type mandb_exec_t;
        type systemd_passwd_agent_exec_t;
        type gpg_exec_t;
        type checkpolicy_exec_t;
        type systemd_systemctl_exec_t;
        type devicekit_exec_t;
        type plymouth_exec_t;
        type chfn_exec_t;
        type rsync_exec_t;
        type NetworkManager_exec_t;
        type container_runtime_exec_t;
        type groupadd_exec_t;
        type kdumpctl_exec_t;
        type login_exec_t;
        type fusermount_exec_t;
        type httpd_t;
        type tmpfs_t;
        class tcp_socket { name_bind name_connect };
        class sock_file write;
        class file { execute_no_trans create read write open link getattr unlink };
        class dir search;
        class capability { dac_override sys_rawio };
}

#============= neutron_t ==============
allow neutron_t self:capability { dac_override sys_rawio };
allow neutron_t neutron_exec_t:file execute_no_trans;
allow neutron_t NetworkManager_exec_t:file getattr;
allow neutron_t checkpolicy_exec_t:file getattr;
allow neutron_t chfn_exec_t:file getattr;
allow neutron_t chronyc_exec_t:file getattr;
allow neutron_t conmon_exec_t:file getattr;
allow neutron_t container_runtime_exec_t:file getattr;
allow neutron_t crontab_exec_t:file getattr;
allow neutron_t dbusd_exec_t:file getattr;
allow neutron_t devicekit_exec_t:file getattr;
allow neutron_t dmesg_exec_t:file getattr;
allow neutron_t fusermount_exec_t:file getattr;
allow neutron_t gpg_agent_exec_t:file getattr;
allow neutron_t gpg_exec_t:file getattr;
allow neutron_t groupadd_exec_t:file getattr;
allow neutron_t hostname_exec_t:file getattr;
allow neutron_t journalctl_exec_t:file getattr;
allow neutron_t kdumpctl_exec_t:file getattr;
allow neutron_t keepalived_exec_t:file getattr;
allow neutron_t loadkeys_exec_t:file getattr;
allow neutron_t locate_exec_t:file getattr;
allow neutron_t login_exec_t:file getattr;
allow neutron_t lsmd_exec_t:file getattr;
allow neutron_t lsmd_plugin_exec_t:file getattr;
allow neutron_t mandb_exec_t:file getattr;
allow neutron_t mount_exec_t:file getattr;
allow neutron_t passwd_exec_t:file getattr;
allow neutron_t ping_exec_t:file getattr;
allow neutron_t plymouth_exec_t:file getattr;
allow neutron_t policykit_auth_exec_t:file getattr;
allow neutron_t rpmdb_exec_t:file getattr;
allow neutron_t rsync_exec_t:file getattr;
allow neutron_t ssh_agent_exec_t:file getattr;
allow neutron_t ssh_exec_t:file getattr;
allow neutron_t ssh_keygen_exec_t:file getattr;
allow neutron_t su_exec_t:file getattr;
allow neutron_t systemd_hwdb_exec_t:file getattr;
allow neutron_t systemd_notify_exec_t:file getattr;
allow neutron_t systemd_passwd_agent_exec_t:file getattr;
allow neutron_t systemd_systemctl_exec_t:file getattr;
allow neutron_t systemd_tmpfiles_exec_t:file getattr;
allow neutron_t thumb_exec_t:file getattr;
allow neutron_t traceroute_exec_t:file getattr;
allow neutron_t virt_qemu_ga_exec_t:file getattr;
allow neutron_t vlock_exec_t:file getattr;
allow neutron_t tmpfs_t:file { create read write open link getattr unlink };

#============= openvswitch_t ==============
allow openvswitch_t var_run_t:sock_file write;
allow openvswitch_t ovsdb_port_t:tcp_socket name_bind;

#============= openvswitch_load_module_t ==============
allow openvswitch_load_module_t tracefs_t:dir search;

#============= dnsmasq_t ==============
allow dnsmasq_t self:capability dac_override;
EOF
checkmodule -m -M -o ovsofctl.mod ovsofctl.te
semodule_package --outfile ovsofctl.pp --module ovsofctl.mod
semodule -i ovsofctl.pp

echo "Добавление Neutron в исключения firewall"

firewall-cmd --add-port={9696/tcp,6641/tcp,6642/tcp}
firewall-cmd --runtime-to-permanent

echo "Запуск openvswitch"

systemctl enable --now openvswitch

echo "Создание моста br-int"

ovs-vsctl add-br br-int

echo "Запуск ovn-northd"

systemctl enable --now ovn-northd

echo "Создание соединений для северного и южного моста"

ovn-nbctl set-connection ptcp:6641:$NEUTRON_IP -- set connection . inactivity_probe=60000

ovn-sbctl set-connection ptcp:6642:$NEUTRON_IP -- set connection . inactivity_probe=60000 

echo "Добавление моста br-ex с помощью OpenvSwitch"

ovs-vsctl add-br br-ex

echo "Мапим мост br-ex на сетевой интерфейс enp*s0"

enp=$(ip a | grep -E "enp[0-9]s0:" | grep -Eo "enp[2-9]s0")

ovs-vsctl add-port br-ex $enp

echo "Задаем название провайдера сети"

ovs-vsctl set open . external-ids:ovn-bridge-mappings=external:br-ex

echo "Запуск neutron-server"

systemctl enable --now neutron-server

}





function neutron_compute_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Neutron\033[0m"

echo "Установка служб необходимых для работы сервиса Neutron"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-neutron openstack-neutron-ml2 openstack-neutron-ovn-metadata-agent ovn-2021-host

echo "Редактирование конфига /etc/neutron/neutron.conf"

crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins ovn-router
crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips true
crudini --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://neutron:$NEUTRON_PASS@$NOVA_HOSTNAME
crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
crudini --set /etc/neutron/neutron.conf DEFAULT state_path /var/lib/neutron
crudini --set /etc/neutron/neutron.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name default
crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name default
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
crudini --set /etc/neutron/neutron.conf keystone_authtoken password $NEUTRON_PASS
crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp

echo "Редактирование конфига /etc/sysconfig/openvswitch"

sed -c -i 's/OPTIONS=/"/"/OPTIONS=/"--ovsdb-server-options=/'--remote=ptcp:6640:127.0.0.1/'/"/' /etc/sysconfig/openvswitch

echo "Редактирование конфига /etc/neutron/plugins/ml2/ml2_conf.ini"

crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat,geneve
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types geneve
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers ovn
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 overlay_ip_version 4
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks *
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_geneve vni_ranges 1:65536
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_geneve max_header_size 38
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group true
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_nb_connection tcp:$NEUTRON_IP:6641
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_sb_connection tcp:$NEUTRON_IP:6642
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_l3_scheduler leastloaded
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_metadata_enabled true

echo "Редактирование конфига /etc/nova/nova.conf"

crudini --set /etc/nova/nova.conf DEFAULT vif_plugging_is_fatal true
crudini --set /etc/nova/nova.conf DEFAULT vif_plugging_timeout 300
crudini --set /etc/nova/nova.conf neutron auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/nova/nova.conf neutron auth_type password
crudini --set /etc/nova/nova.conf neutron project_domain_name default
crudini --set /etc/nova/nova.conf neutron user_domain_name default
crudini --set /etc/nova/nova.conf neutron region_name RegionOne
crudini --set /etc/nova/nova.conf neutron project_name service
crudini --set /etc/nova/nova.conf neutron username neutron
crudini --set /etc/nova/nova.conf neutron password $NEUTRON_PASS
crudini --set /etc/nova/nova.conf neutron service_metadata_proxy true
crudini --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret $METADATA_SECRET

echo "Редактирование конфига /etc/neutron/neutron_ovn_metadata_agent.ini"

crudini --set /etc/neutron/neutron_ovn_metadata_agent.ini DEFAULT nova_metadata_host $NOVA_HOSTNAME
crudini --set /etc/neutron/neutron_ovn_metadata_agent.ini DEFAULT metadata_proxy_shared_secret $METADATA_SECRET
crudini --set /etc/neutron/neutron_ovn_metadata_agent.ini agent root_helper "sudo neutron-rootwrap /etc/neutron/rootwrap.conf"
crudini --set /etc/neutron/neutron_ovn_metadata_agent.ini ovs ovsdb_connection tcp:127.0.0.1:6640
crudini --set /etc/neutron/neutron_ovn_metadata_agent.ini ovn ovn_sb_connection tcp:$NEUTRON_IP:6642

echo "Установка openstack-selinux"

dnf --enablerepo=centos-openstack-zed -y install openstack-selinux 

echo "Изменение политик SELinux касательно Neutron"

setsebool -P neutron_can_network on
setsebool -P daemons_enable_cluster_mode on
cat << EOF > ovsofctl.te
module ovsofctl 1.0;

require {
        type neutron_t;
        type neutron_exec_t;
        type neutron_t;
        type dnsmasq_t;
        type openvswitch_load_module_t;
        type tracefs_t;
        type var_run_t;
        type openvswitch_t;
        type ovsdb_port_t;
        class sock_file write;
        class file execute_no_trans;
        class dir search;
        class tcp_socket name_bind;
        class capability { dac_override sys_rawio };
}

#============= neutron_t ==============
allow neutron_t self:capability { dac_override sys_rawio };
allow neutron_t neutron_exec_t:file execute_no_trans;

#============= openvswitch_t ==============
allow openvswitch_t var_run_t:sock_file write;
allow openvswitch_t ovsdb_port_t:tcp_socket name_bind;

#============= openvswitch_load_module_t ==============
allow openvswitch_load_module_t tracefs_t:dir search;

#============= dnsmasq_t ==============
allow dnsmasq_t self:capability dac_override;
EOF
checkmodule -m -M -o ovsofctl.mod ovsofctl.te
semodule_package --outfile ovsofctl.pp --module ovsofctl.mod
semodule -i ovsofctl.pp

echo "Создание символической ссылки /etc/neutron/plugin.ini на файл /etc/neutron/plugins/ml2/ml2_conf.ini"

ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

echo "Запуск openvswitch и ovn-controller"

systemctl enable --now openvswitch
systemctl enable --now ovn-controller

echo "Конфигурирование OVN соединений"

ovs-vsctl set open . external-ids:ovn-remote=tcp:$NEUTRON_IP:6642 
ovs-vsctl set open . external-ids:ovn-encap-type=geneve
ovs-vsctl set open . external-ids:ovn-encap-ip=$HOST_IP

echo "Добавление моста br-ex с помощью OpenvSwitch"

ovs-vsctl add-br br-ex

echo "Мапим мост br-ex на сетевой интерфейс enp*s0"

enp=$(ip a | grep -E "enp[0-9]s0:" | grep -Eo "enp[2-9]s0")

ovs-vsctl add-port br-ex $enp

echo "Задаем название провайдера сети"

ovs-vsctl set open . external-ids:ovn-bridge-mappings=external:br-ex

echo "Перезапуск openstack-nova-compute"

systemctl restart openstack-nova-compute

echo "Запуск neutron-ovn-metadata-agent "

systemctl enable --now neutron-ovn-metadata-agent 
}




function horizon_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Horizon\033[0m"

echo "Установка сервиса Horizon"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-dashboard

echo "Редактирование конфига /etc/openstack-dashboard/local_settings"

crudini --set /etc/openstack-dashboard/local_settings "" OPENSTACK_HOST "\"$NOVA_HOSTNAME\""
crudini --set /etc/openstack-dashboard/local_settings "" ALLOWED_HOSTS ["'*'"]
crudini --set /etc/openstack-dashboard/local_settings "" OPENSTACK_KEYSTONE_URL "\"http://$NOVA_HOSTNAME:5000\""
crudini --set /etc/openstack-dashboard/local_settings "" TIME_ZONE "\"$TIME_ZONE\""
cat << EOF >> /etc/openstack-dashboard/local_settings
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'
CACHES = {
    'default': {
         'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
         'LOCATION': '$NOVA_HOSTNAME:11211',
    }
}
OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 3,
}
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "default"
SESSION_TIMEOUT = 3600
WEBROOT = '/dashboard/'
LOGIN_URL = '/dashboard/auth/login/'
LOGOUT_URL = '/dashboard/auth/logout/'
LOGIN_REDIRECT_URL = '/dashboard/'
EOF

echo "Редактирование конфига /etc/httpd/conf.d/openstack-dashboard.conf"

sed -i -c '/WSGISocketPrefix/a WSGIApplicationGroup %{GLOBAL} ' /etc/httpd/conf.d/openstack-dashboard.conf
sed -i -c 's/wsgi\/django.wsgi/wsgi.py/' /etc/httpd/conf.d/openstack-dashboard.conf
sed -i -c 's/\/wsgi>/>/' /etc/httpd/conf.d/openstack-dashboard.conf

echo "Изменение политик SELinux касательно Horizon"

setsebool -P httpd_can_network_connect on

echo "Добавление Horizon в исключения firewall"

firewall-cmd --add-service=http
firewall-cmd --runtime-to-permanent

echo "Перезапуск httpd, memcached и openstack-nova-api"

systemctl restart httpd
systemctl restart memcached
systemctl restart openstack-nova-api
}



function telemetry_controller_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Telemetry\033[0m"

echo "Создание пользователя gnocchi"

source ~/keystonerc_adm
openstack user create --domain default --project service --password $GNOCCHI_PASS gnocchi

echo "Присваивание пользователю gnocchi роли admin в проекте serivce"

openstack role add --project service --user gnocchi admin 

echo "Создание сервиса gnocchi"

openstack service create --name gnocchi --description "Metric Service" metric

echo "Создание точек входа в сервиса gnocchi"

openstack endpoint create --region RegionOne metric public http://$GNOCCHI_HOSTNAME:8041
openstack endpoint create --region RegionOne metric internal http://$GNOCCHI_HOSTNAME:8041
openstack endpoint create --region RegionOne metric admin http://$GNOCCHI_HOSTNAME:8041

echo "Создание пользователя ceilometer"

openstack user create --domain default --project service --password $CEILOMETER_PASS ceilometer

echo "Присваивание пользователю ceilometer роли admin в проекте serivce"

openstack role add --project service --user ceilometer admin 

echo "Создание сервиса ceilometer"

openstack service create --name ceilometer --description "Telemetry Service" metering

echo "Создание пользователя aodh"

openstack user create --domain default --project service --password $AODH_PASS aodh

echo "Присваивание пользователю aodh роли admin в проекте serivce"

openstack role add --project service --user aodh admin 

echo "Создание сервиса aodh"

openstack service create --name aodh --description "Telemetry" alarming

echo "Создание точек входа в сервиса aodh"

openstack endpoint create --region RegionOne alarming public http://$AODH_HOSTNAME:8042
openstack endpoint create --region RegionOne alarming internal http://$AODH_HOSTNAME:8042
openstack endpoint create --region RegionOne alarming admin http://$AODH_HOSTNAME:8042

echo "Создание БД для сервиса Aodh"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE aodh;"

echo "Выдача прав на работу с БД пользователю aodh"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON aodh.* TO 'aodh'@'localhost' IDENTIFIED BY '$AODH_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON aodh.* TO 'aodh'@'%' IDENTIFIED BY '$AODH_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание БД для сервиса Gnocchi"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE gnocchi"

echo "Выдача прав на работу с БД пользователю gnocchi;"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON gnocchi.* TO 'gnocchi'@'localhost' IDENTIFIED BY '$GNOCCHI_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON gnocchi.* TO 'gnocchi'@'%' IDENTIFIED BY '$GNOCCHI_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя RabbitMQ для сервисов Aodh, Gnocchi и Ceilometer"

rabbitmqctl add_user aodh $AODH_PASS
rabbitmqctl add_user gnocchi $GNOCCHI_PASS
rabbitmqctl add_user ceilometer $CEILOMETER_PASS

echo "Выдача созданным пользователям RabbitMQ всех разрешений"

rabbitmqctl set_permissions aodh ".*" ".*" ".*"
rabbitmqctl set_permissions gnocchi ".*" ".*" ".*"
rabbitmqctl set_permissions ceilometer ".*" ".*" ".*"

echo "Установка служб необходимых для работы сервиса Gnocchi"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install python3-gnocchiclient

echo "Установка служб необходимых для работы сервиса Ceilometer"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install python3-ceilometerclient

echo "Установка служб необходимых для работы сервиса Aodh"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install python3-aodhclient

echo "Редактирование конфига /etc/glance/glance-api.conf"

crudini --set /etc/glance/glance-api.conf oslo_messaging_notifications driver messagingv2
crudini --set /etc/glance/glance-api.conf oslo_messaging_notifications transport_url rabbit://glance:$GLANCE_PASS@$NOVA_HOSTNAME

echo "Редактирование конфига /etc/cinder/cinder.conf"

crudini --set /etc/cinder/cinder.conf oslo_messaging_notifications driver messagingv2
crudini --set /etc/cinder/cinder.conf oslo_messaging_notifications transport_url rabbit://cinder:$CINDER_PASS@$NOVA_HOSTNAME

echo "Перезапуск openstack-glance-api, openstack-cinder-api и openstack-cinder-scheduler "

systemctl restart openstack-glance-api
systemctl restart openstack-cinder-api
systemctl restart openstack-cinder-scheduler
}



function telemetry_network_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Telemetry\033[0m"

echo "Установка служб необходимых для работы сервиса Gnocchi"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-gnocchi-api openstack-gnocchi-metricd python3-gnocchiclient httpd python3-mod_wsgi

echo "Редактирование конфига /etc/gnocchi/gnocchi.conf"

crudini --set /etc/gnocchi/gnocchi.conf DEFAULT log_dir /var/log/gnocchi
crudini --set /etc/gnocchi/gnocchi.conf api auth_mode keystone
crudini --set /etc/gnocchi/gnocchi.conf database backend sqlalchemy
crudini --set /etc/gnocchi/gnocchi.conf indexer url mysql+pymysql://gnocchi:$GNOCCHI_PASS@$NOVA_HOSTNAME/gnocchi
crudini --set /etc/gnocchi/gnocchi.conf storage file_path /var/lib/gnocchi
crudini --set /etc/gnocchi/gnocchi.conf storage driver file
crudini --set /etc/gnocchi/gnocchi.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/gnocchi/gnocchi.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/gnocchi/gnocchi.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/gnocchi/gnocchi.conf keystone_authtoken auth_type password
crudini --set /etc/gnocchi/gnocchi.conf keystone_authtoken project_domain_name default
crudini --set /etc/gnocchi/gnocchi.conf keystone_authtoken user_domain_name default
crudini --set /etc/gnocchi/gnocchi.conf keystone_authtoken project_name service
crudini --set /etc/gnocchi/gnocchi.conf keystone_authtoken username gnocchi
crudini --set /etc/gnocchi/gnocchi.conf keystone_authtoken password $GNOCCHI_PASS
crudini --set /etc/gnocchi/gnocchi.conf keystone_authtoken service_token_roles_required true

echo "Редактирование конфига /etc/httpd/conf.d/10-gnocchi_wsgi.conf"

cat << EOF > /etc/httpd/conf.d/10-gnocchi_wsgi.conf
Listen 8041
<VirtualHost *:8041>
  <Directory /usr/bin>
    AllowOverride None
    Require all granted
  </Directory>

  CustomLog /var/log/httpd/gnocchi_wsgi_access.log combined
  ErrorLog /var/log/httpd/gnocchi_wsgi_error.log
  WSGIApplicationGroup %{GLOBAL}
  WSGIDaemonProcess gnocchi display-name=gnocchi_wsgi user=gnocchi group=gnocchi processes=6 threads=6
  WSGIProcessGroup gnocchi
  WSGIScriptAlias / /usr/bin/gnocchi-api
</VirtualHost>
EOF

echo "Инициализация БД gnocchi"

su -s /bin/bash gnocchi -c "gnocchi-upgrade"

echo "Изменение политик SELinux касательно Gnocchi"

setsebool -P httpd_can_network_connect on
semanage port -a -t http_port_t -p tcp 8041

echo "Добавление Gnocchi в исключения firewall"

firewall-cmd --add-port=8041/tcp
firewall-cmd --runtime-to-permanent

echo "Перезапуск httpd"

systemctl enable --now httpd
systemctl restart httpd

echo "Запуск openstack-gnocchi-api и openstack-gnocchi-metricd"

systemctl enable --now openstack-gnocchi-metricd

echo "Установка служб необходимых для работы сервиса Ceilometer"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-ceilometer-central openstack-ceilometer-notification python3-ceilometerclient

echo "Редактирование конфига /etc/ceilometer/ceilometer.conf"

crudini --set /etc/ceilometer/ceilometer.conf DEFAULT transport_url rabbit://ceilometer:$CEILOMETER_PASS@$NOVA_HOSTNAME
crudini --set /etc/ceilometer/ceilometer.conf api auth_mode keystone
crudini --set /etc/ceilometer/ceilometer.conf dispatcher_gnocchi filter_service_activity false
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_type password
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken project_domain_name default
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken user_domain_name default
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken project_name service
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken username gnocchi
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken password $GNOCCHI_PASS
crudini --set /etc/ceilometer/ceilometer.conf service_credentials auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/ceilometer/ceilometer.conf service_credentials memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/ceilometer/ceilometer.conf service_credentials auth_type password
crudini --set /etc/ceilometer/ceilometer.conf service_credentials project_domain_name default
crudini --set /etc/ceilometer/ceilometer.conf service_credentials user_domain_name default
crudini --set /etc/ceilometer/ceilometer.conf service_credentials project_name service
crudini --set /etc/ceilometer/ceilometer.conf service_credentials username ceilometer
crudini --set /etc/ceilometer/ceilometer.conf service_credentials password $CEILOMETER_PASS

echo "Синхронизация ceilometer с БД gnocchi"

su -s /bin/bash ceilometer -c "ceilometer-upgrade --skip-metering-database"

echo "Запуск openstack-ceilometer-notification и openstack-ceilometer-central"

systemctl enable --now openstack-ceilometer-central
systemctl enable --now openstack-ceilometer-notification 

echo "Установка служб необходимых для работы сервиса Aodh"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-aodh-api openstack-aodh-evaluator openstack-aodh-notifier openstack-aodh-listener openstack-aodh-expirer python3-aodhclient

echo "Редактирование конфига /etc/aodh/aodh.conf"

crudini --set /etc/aodh/aodh.conf DEFAULT transport_url rabbit://aodh:$AODH_PASS@$NOVA_HOSTNAME
crudini --set /etc/aodh/aodh.conf database connection mysql+pymysql://aodh:$AODH_PASS@$NOVA_HOSTNAME/aodh
crudini --set /etc/aodh/aodh.conf DEFAULT auth_strategy keystone
crudini --set /etc/aodh/aodh.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/aodh/aodh.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/aodh/aodh.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/aodh/aodh.conf keystone_authtoken auth_type password
crudini --set /etc/aodh/aodh.conf keystone_authtoken project_domain_name default
crudini --set /etc/aodh/aodh.conf keystone_authtoken user_domain_name default
crudini --set /etc/aodh/aodh.conf keystone_authtoken project_name service
crudini --set /etc/aodh/aodh.conf keystone_authtoken username aodh
crudini --set /etc/aodh/aodh.conf keystone_authtoken password $AODH_PASS
crudini --set /etc/aodh/aodh.conf service_credentials auth_type password
crudini --set /etc/aodh/aodh.conf service_credentials auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/aodh/aodh.conf service_credentials project_domain_name default
crudini --set /etc/aodh/aodh.conf service_credentials user_domain_name default
crudini --set /etc/aodh/aodh.conf service_credentials project_name service
crudini --set /etc/aodh/aodh.conf service_credentials username aodh
crudini --set /etc/aodh/aodh.conf service_credentials password $AODH_PASS

echo "Редактирование конфига /etc/httpd/conf.d/10-aodh_wsgi.conf"

cat << EOF > /etc/httpd/conf.d/10-aodh_wsgi.conf
Listen 8042
<VirtualHost *:8042>
  <Directory /usr/bin>
    AllowOverride None
    Require all granted
  </Directory>

  CustomLog /var/log/httpd/aodh_access.log combined
  ErrorLog /var/log/httpd/aodh_error.log
  WSGIApplicationGroup %{GLOBAL}
  WSGIDaemonProcess aodh-api display-name=aodh_wsgi user=aodh group=aodh processes=6 threads=6
  WSGIProcessGroup aodh-api
  WSGIScriptAlias / /usr/bin/aodh-api
</VirtualHost>
EOF

echo "Инициализация БД aodh"

su -s /bin/bash aodh -c "aodh-dbsync"

echo "Изменение политик SELinux касательно Aodh"

setsebool -P httpd_can_network_connect on
semanage port -a -t http_port_t -p tcp 8042

echo "Добавление Aodh в исключения firewall"

firewall-cmd --add-port=8042/tcp
firewall-cmd --runtime-to-permanent

echo "Перезапуск httpd"

systemctl enable --now httpd
systemctl restart httpd

echo "Запуск openstack-aodh-api, openstack-aodh-notifier, openstack-aodh-listener и openstack-aodh-evaluator"

systemctl enable --now openstack-aodh-notifier
systemctl enable --now openstack-aodh-listener
systemctl enable --now openstack-aodh-evaluator
}



function telemetry_compute_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Telemetry\033[0m"

echo "Установка служб необходимых для работы сервиса Ceilometer"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-ceilometer-compute

echo "Редактирование конфига /etc/ceilometer/ceilometer.conf"

crudini --set /etc/ceilometer/ceilometer.conf DEFAULT transport_url rabbit://ceilometer:$CEILOMETER_PASS@$NOVA_HOSTNAME
crudini --set /etc/ceilometer/ceilometer.conf service_credentials auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/ceilometer/ceilometer.conf service_credentials memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/ceilometer/ceilometer.conf service_credentials auth_type password
crudini --set /etc/ceilometer/ceilometer.conf service_credentials project_domain_name default
crudini --set /etc/ceilometer/ceilometer.conf service_credentials user_domain_name default
crudini --set /etc/ceilometer/ceilometer.conf service_credentials project_name service
crudini --set /etc/ceilometer/ceilometer.conf service_credentials username ceilometer
crudini --set /etc/ceilometer/ceilometer.conf service_credentials password $CEILOMETER_PASS

echo "Редактирование конфига /etc/nova/nova.conf"

crudini --set /etc/nova/nova.conf DEFAULT instance_usage_audit true
crudini --set /etc/nova/nova.conf DEFAULT instance_usage_audit_period hour
crudini --set /etc/nova/nova.conf DEFAULT notifi_on_stage_change vm_and_task_state
crudini --set /etc/nova/nova.conf oslo_messaging_notifications driver messagingv2

echo "Запуск openstack-ceilometer-compute"

systemctl enable --now openstack-ceilometer-compute

echo "Перезапуск openstack-nova-compute"

systemctl restart openstack-nova-compute
}




function heat_controller_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Heat\033[0m"

echo "Создание пользователя heat"

source ~/keystonerc_adm
openstack user create --domain default --project service --password $HEAT_PASS heat

echo "Присваивание пользователю heat роли admin в проекте serivce"

openstack role add --project service --user heat admin

echo "Создание роли heat_stack_owner"

openstack role create heat_stack_owner

echo "Создание роли heat_stack_user"

openstack role create heat_stack_user

echo "Присваивание пользователю admin роли heat_stack_owner"

openstack role add --project admin --user admin heat_stack_owner

echo "Создание сервиса heat"

openstack service create --name heat --description "Orchestration" orchestration

echo "Создание сервиса heat-cfn"

openstack service create --name heat-cfn --description "Orchestration" cloudformation

echo "Создание точек входа в сервиса heat"

openstack endpoint create --region RegionOne orchestration public http://$HEAT_HOSTNAME:8004/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne orchestration internal http://$HEAT_HOSTNAME:8004/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne orchestration admin http://$HEAT_HOSTNAME:8004/v1/%\(tenant_id\)s

echo "Создание точек входа в сервиса heat-cfn"

openstack endpoint create --region RegionOne cloudformation public http://$HEAT_HOSTNAME:8000/v1
openstack endpoint create --region RegionOne cloudformation internal http://$HEAT_HOSTNAME:8000/v1
openstack endpoint create --region RegionOne cloudformation admin http://$HEAT_HOSTNAME:8000/v1

echo "Создание домена heat"

openstack domain create --description "Stack Projects and Users" heat

echo "Создание пользователя heat_domain_admin в домене heat"

openstack user create --domain heat --password $HEAT_PASS heat_domain_admin

echo "Присваивание пользователю heat_domain_admin роли admin в домене heat"

openstack role add --domain heat --user-domain heat --user heat_domain_admin admin

echo "Создание БД для сервиса Heat"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE heat;"

echo "Выдача прав на работу с БД пользователю heat"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'localhost' IDENTIFIED BY '$HEAT_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'%' IDENTIFIED BY '$HEAT_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя RabbitMQ для сервиса Heat"

rabbitmqctl add_user heat $HEAT_PASS

echo "Выдача созданному пользователю RabbitMQ всех разрешений"

rabbitmqctl set_permissions heat ".*" ".*" ".*"

echo "Установка служб необходимых для работы сервиса Heat"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install python3-heatclient
}




function heat_network_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Heat\033[0m"

echo "Установка служб необходимых для работы сервиса Heat"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-heat-api openstack-heat-api-cfn openstack-heat-engine python3-heatclient

echo "Редактирование конфига /etc/heat/heat.conf"

crudini --set /etc/heat/heat.conf DEFAULT deferred_auth_method trusts
crudini --set /etc/heat/heat.conf DEFAULT trusts_delegated_roles heat_stack_owner
crudini --set /etc/heat/heat.conf DEFAULT heat_metadata_server_url http://$HEAT_HOSTNAME:8000
crudini --set /etc/heat/heat.conf DEFAULT heat_waitcondition_server_url http://$HEAT_HOSTNAME:8000/v1/waitcondition
crudini --set /etc/heat/heat.conf DEFAULT heat_stack_user_role heat_stack_user
crudini --set /etc/heat/heat.conf DEFAULT stack_user_domain_name heat
crudini --set /etc/heat/heat.conf DEFAULT stack_domain_admin heat_domain_admin
crudini --set /etc/heat/heat.conf DEFAULT stack_domain_admin_password $HEAT_PASS
crudini --set /etc/heat/heat.conf DEFAULT transport_url rabbit://heat:$HEAT_PASS@$NOVA_HOSTNAME
crudini --set /etc/heat/heat.conf database connection mysql+pymysql://heat:$HEAT_PASS@$NOVA_HOSTNAME/heat
crudini --set /etc/heat/heat.conf clients_keystone auth_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/heat/heat.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/heat/heat.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/heat/heat.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/heat/heat.conf keystone_authtoken auth_type password
crudini --set /etc/heat/heat.conf keystone_authtoken project_domain_name default
crudini --set /etc/heat/heat.conf keystone_authtoken user_domain_name default
crudini --set /etc/heat/heat.conf keystone_authtoken project_name service
crudini --set /etc/heat/heat.conf keystone_authtoken username heat
crudini --set /etc/heat/heat.conf keystone_authtoken password $HEAT_PASS
crudini --set /etc/heat/heat.conf trustee auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/heat/heat.conf trustee auth_type password
crudini --set /etc/heat/heat.conf trustee user_domain_name default
crudini --set /etc/heat/heat.conf trustee username heat
crudini --set /etc/heat/heat.conf trustee password $HEAT_PASS

echo "Инициализация БД heat"

su -s /bin/bash heat -c "heat-manage db_sync"

echo "Добавление Heat в исключения firewall"

firewall-cmd --add-port={8000/tcp,8004/tcp}
firewall-cmd --runtime-to-permanent

echo "Запуск openstack-heat-api, openstack-heat-api-cfn и openstack-heat-engine"

systemctl enable --now openstack-heat-api
systemctl enable --now openstack-heat-api-cfn
systemctl enable --now openstack-heat-engine
}



function barbican_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Barbican\033[0m"

echo "Создание пользователя barbican"

source ~/keystonerc_adm
openstack user create --domain default --project service --password $BARBICAN_PASS barbican 

echo "Присваивание пользователю barbican роли admin в проекте serivce"

openstack role add --project service --user barbican admin

echo "Создание сервиса barbican"

openstack service create --name barbican --description "Key Manager" key-manager

echo "Создание точек входа в сервис barbican"

openstack endpoint create --region RegionOne key-manager public http://$NOVA_HOSTNAME:9311
openstack endpoint create --region RegionOne key-manager internal http://$NOVA_HOSTNAME:9311
openstack endpoint create --region RegionOne key-manager admin http://$NOVA_HOSTNAME:9311

echo "Создание БД для сервиса barbican"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE barbican;"

echo "Выдача прав на работу с БД пользователю barbican"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON barbican.* TO 'barbican'@'localhost' IDENTIFIED BY '$BARBICAN_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON barbican.* TO 'barbican'@'%' IDENTIFIED BY '$BARBICAN_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя RabbitMQ для сервиса Barbican"

rabbitmqctl add_user barbican $BARBICAN_PASS

echo "Выдача созданному пользователю RabbitMQ всех разрешений"

rabbitmqctl set_permissions barbican ".*" ".*" ".*"

echo "Установка служб необходимых для работы сервиса barbican"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-barbican

echo "Редактирование конфига /etc/barbican/barbican.conf"

crudini --set /etc/barbican/barbican.conf DEFAULT host_href http://$NOVA_HOSTNAME:9311
crudini --set /etc/barbican/barbican.conf DEFAULT log_file /var/log/barbican/api.log
crudini --set /etc/barbican/barbican.conf DEFAULT sql_connection mysql+pymysql://barbican:$BARBICAN_PASS@$NOVA_HOSTNAME/barbican
crudini --set /etc/barbican/barbican.conf DEFAULT transport_url rabbit://barbican:$BARBICAN_PASS@$NOVA_HOSTNAME
crudini --set /etc/barbican/barbican.conf oslo_policy policy_file /etc/barbican/policy.json
crudini --set /etc/barbican/barbican.conf oslo_policy policy_default_rule default
crudini --set /etc/barbican/barbican.conf secretstore namespace barbican.secretstore.plugin
crudini --set /etc/barbican/barbican.conf secretstore enabled_secretstore_plugins store_crypto
crudini --set /etc/barbican/barbican.conf crypto namespace barbican.crypto.plugin
crudini --set /etc/barbican/barbican.conf crypto enabled_crypto_plugins simple_crypto
crudini --set /etc/barbican/barbican.conf simple_crypto_plugin kek 'YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY='
crudini --set /etc/barbican/barbican.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/barbican/barbican.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/barbican/barbican.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/barbican/barbican.conf keystone_authtoken auth_type password
crudini --set /etc/barbican/barbican.conf keystone_authtoken project_domain_name default
crudini --set /etc/barbican/barbican.conf keystone_authtoken user_domain_name default
crudini --set /etc/barbican/barbican.conf keystone_authtoken project_name service
crudini --set /etc/barbican/barbican.conf keystone_authtoken username barbican
crudini --set /etc/barbican/barbican.conf keystone_authtoken password $BARBICAN_PASS

echo "Инициализация БД barbican"

su -s /bin/bash barbican -c "barbican-manage db upgrade"

echo "Изменение политик SELinux касательно Barbican"

semanage port -a -t http_port_t -p tcp 9311

echo "Добавление Barbican в исключения firewall"

firewall-cmd --add-port=9311/tcp
firewall-cmd --runtime-to-permanent

echo "Запуск openstack-barbican-api"

systemctl enable --now openstack-barbican-api
}



function manila_controller_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Manila\033[0m"

echo "Создание пользователя manila"

source ~/keystonerc_adm
openstack user create --domain default --project service --password $MANILA_PASS manila 

echo "Присваивание пользователю manila роли admin в проекте serivce"

openstack role add --project service --user manila admin

echo "Создание сервиса manila"

openstack service create --name manila --description "Shared Filesystem V2" sharev2

echo "Создание точек входа в сервис manila"

openstack endpoint create --region RegionOne sharev2 public http://$NOVA_HOSTNAME:8786/v2
openstack endpoint create --region RegionOne sharev2 internal http://$NOVA_HOSTNAME:8786/v2
openstack endpoint create --region RegionOne sharev2 admin http://$NOVA_HOSTNAME:8786/v2

echo "Создание БД для сервиса Manila"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE manila;"

echo "Выдача прав на работу с БД пользователю manila"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON manila.* TO 'manila'@'localhost' IDENTIFIED BY '$MANILA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON manila.* TO 'manila'@'%' IDENTIFIED BY '$MANILA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя RabbitMQ для сервиса Manila"

rabbitmqctl add_user manila $MANILA_PASS

echo "Выдача созданному пользователю RabbitMQ всех разрешений"

rabbitmqctl set_permissions manila ".*" ".*" ".*"

echo "Установка служб необходимых для работы Manila"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-manila python3-manilaclient

echo "Редактирование конфига /etc/manila/manila.conf"

crudini --set /etc/manila/manila.conf DEFAULT rootwrap_config /etc/manila/rootwrap.conf
crudini --set /etc/manila/manila.conf DEFAULT api_paste_config /etc/manila/api-paste.ini
crudini --set /etc/manila/manila.conf DEFAULT auth_strategy keystone
crudini --set /etc/manila/manila.conf DEFAULT default_share_type default_share_type
crudini --set /etc/manila/manila.conf DEFAULT share_name_template share-%s
crudini --set /etc/manila/manila.conf DEFAULT state_path /var/lib/manila
crudini --set /etc/manila/manila.conf DEFAULT transport_url rabbit://manila:$MANILA_PASS@$NOVA_HOSTNAME
crudini --set /etc/manila/manila.conf database connection mysql+pymysql://manila:$MANILA_PASS@$NOVA_HOSTNAME/manila
crudini --set /etc/manila/manila.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/manila/manila.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/manila/manila.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/manila/manila.conf keystone_authtoken auth_type password
crudini --set /etc/manila/manila.conf keystone_authtoken project_domain_name default
crudini --set /etc/manila/manila.conf keystone_authtoken user_domain_name default
crudini --set /etc/manila/manila.conf keystone_authtoken project_name service
crudini --set /etc/manila/manila.conf keystone_authtoken username manila
crudini --set /etc/manila/manila.conf keystone_authtoken password $MANILA_PASS
crudini --set /etc/manila/manila.conf oslo_concurrency lock_path /var/lib/manila/tmp
crudini --set /etc/manila/manila.conf oslo_policy policy_file /etc/manila/policy.yaml

echo "Выдача прав на файл /etc/manila/policy.yaml сервису Manila"

chmod 640 /etc/manila/policy.yaml
chgrp manila /etc/manila/policy.yaml

echo "Инициализация БД manila"

su -s /bin/bash manila -c "manila-manage db sync"

echo "Изменение политик SELinux касательно Manila"

semanage port -a -t http_port_t -p tcp 8786

echo "Добавление Manila в исключения firewall"

firewall-cmd --add-port=8786/tcp
firewall-cmd --runtime-to-permanent

echo "Запуск openstack-manila-api и openstack-manila-scheduler"

systemctl enable --now openstack-manila-api
systemctl enable --now openstack-manila-scheduler
}




function manila_storage_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Manila\033[0m"

echo "Установка служб необходимых для работы Manila"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-manila-share python3-manilaclient python3-PyMySQL python3-mysqlclient dnf nfs-utils nfs4-acl-tools targetcli

echo "Редактирование конфига /etc/manila/manila.conf"

crudini --set /etc/manila/manila.conf DEFAULT my_ip $HOST_IP
crudini --set /etc/manila/manila.conf DEFAULT rootwrap_config /etc/manila/rootwrap.conf
crudini --set /etc/manila/manila.conf DEFAULT api_paste_config /etc/manila/api-paste.ini
crudini --set /etc/manila/manila.conf DEFAULT auth_strategy keystone
crudini --set /etc/manila/manila.conf DEFAULT default_share_type default_share_type
crudini --set /etc/manila/manila.conf DEFAULT enabled_share_protocols NFS
crudini --set /etc/manila/manila.conf DEFAULT transport_url rabbit://manila:$MANILA_PASS@$NOVA_HOSTNAME
crudini --set /etc/manila/manila.conf DEFAULT enabled_share_backends lvm
crudini --set /etc/manila/manila.conf DEFAULT state_path /var/lib/manila
crudini --set /etc/manila/manila.conf database connection mysql+pymysql://manila:$MANILA_PASS@$NOVA_HOSTNAME/manila
crudini --set /etc/manila/manila.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/manila/manila.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/manila/manila.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/manila/manila.conf keystone_authtoken auth_type password
crudini --set /etc/manila/manila.conf keystone_authtoken project_domain_name default
crudini --set /etc/manila/manila.conf keystone_authtoken user_domain_name default
crudini --set /etc/manila/manila.conf keystone_authtoken project_name service
crudini --set /etc/manila/manila.conf keystone_authtoken username manila
crudini --set /etc/manila/manila.conf keystone_authtoken password $MANILA_PASS
crudini --set /etc/manila/manila.conf oslo_concurrency lock_path /var/lib/manila/tmp
crudini --set /etc/manila/manila.conf lvm share_backend_name LVM
crudini --set /etc/manila/manila.conf lvm share_driver manila.share.drivers.lvm.LVMShareDriver
crudini --set /etc/manila/manila.conf lvm driver_handles_share_servers false
crudini --set /etc/manila/manila.conf lvm lvm_share_volume_group manila-volumes
crudini --set /etc/manila/manila.conf lvm lvm_share_export_ips $HOST_IP

echo "Настройка запуска сервиса Manila"

SYSTEMD_EDITOR=tee systemctl edit sddm <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/manila-share --config-file /etc/manila/manila.conf --logfile /var/log/manila/share.log
EOF
mkdir /var/lib/manila
chown manila. /var/lib/manila

echo "Смена языка системы на английский, так как это фиксит некоторые баги"

localectl set-locale LANG=C.UTF-8

echo "Добавление Manila в исключения firewall"

firewall-cmd --add-service=nfs
firewall-cmd --runtime-to-permanent

echo "Создание lvm-группы для сервиса Manila"

vgcreate manila-volumes /dev/vdc

echo "Запуск openstack-manila-share и nfs-server "

systemctl enable --now openstack-manila-share
systemctl enable --now nfs-server
}



function designate_controller_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Designate\033[0m"

echo "Создание пользователя designate"

source ~/keystonerc_adm
openstack user create --domain default --project service --password $DESIGNATE_PASS designate 

echo "Присваивание пользователю designate роли admin в проекте serivce"

openstack role add --project service --user designate admin

echo "Создание сервиса designate"

openstack service create --name designate --description "DNS Service" dns

echo "Создание точек входа в сервис designate"

openstack endpoint create --region RegionOne dns public http://$DESIGNATE_HOSTNAME:9001
openstack endpoint create --region RegionOne dns internal http://$DESIGNATE_HOSTNAME:9001
openstack endpoint create --region RegionOne dns admin http://$DESIGNATE_HOSTNAME:9001

echo "Создание БД для сервиса Designate"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE designate;"

echo "Выдача прав на работу с БД пользователю designate"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON designate.* TO 'designate'@'localhost' IDENTIFIED BY '$DESIGNATE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON designate.* TO 'designate'@'%' IDENTIFIED BY '$DESIGNATE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя RabbitMQ для сервиса Designate"

rabbitmqctl add_user designate $DESIGNATE_PASS

echo "Выдача созданному пользователю RabbitMQ всех разрешений"

rabbitmqctl set_permissions designate ".*" ".*" ".*"

echo "Установка служб необходимых для работы сервиса Designate"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install python3-designateclient
}




function desigante_network_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Designate\033[0m"

echo "Установка служб необходимых для работы сервиса Designate"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-designate-api openstack-designate-central openstack-designate-worker openstack-designate-producer openstack-designate-mdns python3-designateclient bind bind-utils

echo "Создание rndc-ключа для сервиса Designate"

rndc-confgen -a -k designate -c /etc/designate.key
chown named:designate /etc/designate.key
chmod 640 /etc/designate.key

echo "Редактирование конфига /etc/named.conf"

cat << EOF > /etc/named.conf
options {
        listen-on port 53 { any; };
        listen-on-v6 port 53 { none; };
        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        allow-query     { localhost; $HOST_NETWORK/24; };
        allow-new-zones yes;
        request-ixfr no;
        recursion no;
        bindkeys-file "/etc/named.iscdlv.key";
        managed-keys-directory "/var/named/dynamic";
        pid-file "/run/named/named.pid";
        session-keyfile "/run/named/session.key";
};
include "/etc/designate.key";
controls {
    inet 0.0.0.0 port 953
    allow { localhost; } keys { "designate"; };
};
logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};
zone "." IN {
        type hint;
        file "named.ca";
};
EOF
chown -R named. /var/named

echo "Запуск named"

systemctl enable --now named

echo "Редактирование конфига /etc/designate/designate.conf"

crudini --set /etc/designate/designate.conf DEFAULT transport_url rabbit://designate:$DESIGNATE_PASS@$NOVA_HOSTNAME
crudini --set /etc/designate/designate.conf DEFAULT log_dir /var/log/designate
crudini --set /etc/designate/designate.conf DEFAULT root_helper "sudo designate-rootwrap /etc/designate/rootwrap.conf"
crudini --set /etc/designate/designate.conf database connection mysql+pymysql://designate:$DESIGNATE_PASS@$NOVA_HOSTNAME/designate
crudini --set /etc/designate/designate.conf service:api auth_strategy keystone
crudini --set /etc/designate/designate.conf service:api api_base_uri http://$DESIGNATE_HOSTNAME:9001
crudini --set /etc/designate/designate.conf service:api enable_api_v2 true
crudini --set /etc/designate/designate.conf service:api enabled_extensions_v2 "quotas, reports"
crudini --set /etc/designate/designate.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/designate/designate.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/designate/designate.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/designate/designate.conf keystone_authtoken auth_type password
crudini --set /etc/designate/designate.conf keystone_authtoken project_domain_name default
crudini --set /etc/designate/designate.conf keystone_authtoken user_domain_name default
crudini --set /etc/designate/designate.conf keystone_authtoken project_name service
crudini --set /etc/designate/designate.conf keystone_authtoken username designate
crudini --set /etc/designate/designate.conf keystone_authtoken password $DESIGNATE_PASS
crudini --set /etc/designate/designate.conf service:worker enabled true
crudini --set /etc/designate/designate.conf service:worker notify true
crudini --set /etc/designate/designate.conf storage:sqlalchemy connection mysql+pymysql://designate:$DESIGNATE_PASS@$NOVA_HOSTNAME/designate

echo "Инициализация БД designate"

su -s /bin/bash -c "designate-manage database sync" designate

echo "Запуск designate-central и designate-api"

systemctl enable --now designate-central
systemctl enable --now designate-api

echo "Редактирование конфига /etc/designate/pools.yaml"

cat << EOF > /etc/designate/pools.yaml
- name: default
  description: Default Pool
  attributes: {}
  ns_records:
    - hostname: $NOVA_HOSTNAME.
      priority: 1
  nameservers:
    - host: $HOST_IP
      port: 53
  targets:
    - type: bind9
      description: BIND9 Server
      masters:
        - host: $HOST_IP
          port: 5354
      options:
        host: $HOST_IP
        port: 53
        rndc_host: $HOST_IP
        rndc_port: 953
        rndc_key_file: /etc/designate.key
EOF
chmod 640 /etc/designate/pools.yaml
chgrp designate /etc/designate/pools.yaml

echo "Обновление пула в БД designate"

su -s /bin/bash -c "designate-manage pool update" designate

echo "Изменение политик SELinux касательно Designate"

setsebool -P named_write_master_zones on

echo "Добавление Designate в исключения firewall"

firewall-cmd --add-service=dns
firewall-cmd --add-port={5354/tcp,5354/udp,9001/tcp}
firewall-cmd --runtime-to-permanent

echo "Запуск designate-worker, designate-producer и designate-mdns"

systemctl enable --now designate-worker 
systemctl enable --now designate-producer
systemctl enable --now designate-mdns
}




function octavia_controller_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Octavia\033[0m"

echo "Создание пользователя octavia"

source ~/keystonerc_adm
openstack user create --domain default --project service --password $OCTAVIA_PASS octavia 

echo "Присваивание пользователю octavia роли admin в проекте serivce"

openstack role add --project service --user octavia admin

echo "Создание сервиса Octavia"

openstack service create --name octavia --description "LBaaS" load-balancer

echo "Создание точек входа в сервис octavia"

openstack endpoint create --region RegionOne load-balancer public http://$OCTAVIA_HOSTNAME:9876
openstack endpoint create --region RegionOne load-balancer internal http://$OCTAVIA_HOSTNAME:9876
openstack endpoint create --region RegionOne load-balancer admin http://$OCTAVIA_HOSTNAME:9876

echo "Создание БД для сервиса octavia"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE octavia;"

echo "Выдача прав на работу с БД пользователю octavia"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON octavia.* TO 'octavia'@'localhost' IDENTIFIED BY '$OCTAVIA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON octavia.* TO 'octavia'@'%' IDENTIFIED BY '$OCTAVIA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя RabbitMQ для сервиса Octavia"

rabbitmqctl add_user octavia $OCTAVIA_PASS

echo "Выдача созданному пользователю RabbitMQ всех разрешений"

rabbitmqctl set_permissions octavia ".*" ".*" ".*"

echo "Установка служб необходимых для создания образа балансировщика нагрузки"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-octavia-diskimage-create debootstrap python3-octaviaclient

echo "Создание образа балансировщика нагрузки"

octavia-diskimage-create.sh -d focal

echo "Добавление созданного образа в сервис Glance"

openstack image create "Amphora" --tag "Amphora" --file amphora-x64-haproxy.qcow2 --disk-format qcow2 --container-format bare --private --project service

echo "Создание flavor для баланировщиков нагрузки"

openstack flavor create --id 100 --vcpus 1 --ram 1024 --disk 5 m1.octavia --private --project service

echo "Создание группы безопасности для баланировщиков нагрузки"

openstack security group create lb-mgmt-sec-group --project service

echo "Добавление правил в группу безопасноти для баланировщиков нагрузки"

openstack security group rule create --protocol icmp --ingress lb-mgmt-sec-group
openstack security group rule create --protocol tcp --dst-port 22:22 lb-mgmt-sec-group
openstack security group rule create --protocol tcp --dst-port 80:80 lb-mgmt-sec-group
openstack security group rule create --protocol tcp --dst-port 443:443 lb-mgmt-sec-group
openstack security group rule create --protocol tcp --dst-port 9443:9443 lb-mgmt-sec-group
}



function octavia_network_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Octavia\033[0m"

echo "Установка служб необходимых для работы сервиса Octavia"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-octavia-api openstack-octavia-health-manager openstack-octavia-housekeeping openstack-octavia-worker

echo "Редактирование конфига /etc/octavia/octavia.conf"

crudini --set /etc/octavia/octavia.conf DEFAULT transport_url rabbit://octavia:$OCTAVIA_PASS@$NOVA_HOSTNAME
crudini --set /etc/octavia/octavia.conf api_settings bind_host 0.0.0.0
crudini --set /etc/octavia/octavia.conf api_settings auth_strategy keystone
crudini --set /etc/octavia/octavia.conf api_settings api_base_uri http://$OCTAVIA_HOSTNAME:9876
crudini --set /etc/octavia/octavia.conf health_manager bind_ip $HOST_IP
crudini --set /etc/octavia/octavia.conf database connection mysql+pymysql://octavia:$OCTAVIA_PASS@$NOVA_HOSTNAME/octavia
crudini --set /etc/octavia/octavia.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/octavia/octavia.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/octavia/octavia.conf service_auth memcached_servers $NOVA_HOSTNAME::11211
crudini --set /etc/octavia/octavia.conf keystone_authtoken auth_type password
crudini --set /etc/octavia/octavia.conf keystone_authtoken project_domain_name default
crudini --set /etc/octavia/octavia.conf keystone_authtoken user_domain_name default
crudini --set /etc/octavia/octavia.conf keystone_authtoken project_name service
crudini --set /etc/octavia/octavia.conf keystone_authtoken username octavia
crudini --set /etc/octavia/octavia.conf keystone_authtoken password $OCTAVIA_PASS
crudini --set /etc/octavia/octavia.conf oslo_messaging topic octavia_prov
crudini --set /etc/octavia/octavia.conf service_auth auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/octavia/octavia.conf service_auth memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/octavia/octavia.conf service_auth auth_type password
crudini --set /etc/octavia/octavia.conf service_auth project_domain_name default
crudini --set /etc/octavia/octavia.conf service_auth user_domain_name default
crudini --set /etc/octavia/octavia.conf service_auth project_name service
crudini --set /etc/octavia/octavia.conf service_auth username octavia
crudini --set /etc/octavia/octavia.conf service_auth password $OCTAVIA_PASS

echo "Инициализация БД octavia"

su -s /bin/bash octavia -c "octavia-db-manage --config-file /etc/octavia/octavia.conf upgrade head"

echo "Изменение политик SELinux касательно Octavia"

semanage port -a -t http_port_t -p tcp 9876

echo "Добавление Octavia в исключения firewall"

firewall-cmd --add-port=9876/tcp
firewall-cmd --runtime-to-permanent

echo "Запуск octavia-api, octavia-health-manager, octavia-housekeeping и octavia-worker"

systemctl enable --now octavia-api
systemctl enable --now octavia-health-manager
systemctl enable --now octavia-housekeeping
systemctl enable --now octavia-worker
}



function magnum_controller_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Magnum\033[0m"

echo "Создание пользователя magnum"
	
source ~/keystonerc_adm
openstack user create --domain default --project service --password $MAGNUM_PASS magnum

echo "Присваивание пользователю magnum роли admin в проекте serivce"

openstack role add --project service --user magnum admin 

echo "Создание сервиса magnum"

openstack service create --name magnum --description "Containers Orchestration" container-infra 

echo "Создание точек входа в сервисы magnum"

openstack endpoint create --region RegionOne container-infra public http://$MAGNUM_HOSTNAME:9511/v1
openstack endpoint create --region RegionOne container-infra internal http://$MAGNUM_HOSTNAME:9511/v1
openstack endpoint create --region RegionOne container-infra admin http://$MAGNUM_HOSTNAME:9511/v1

echo "Создание домена magnum"

openstack domain create --description "Containers projects and users" magnum

echo "Создание пользователя magnum_domain_admin в домене magnum"

openstack user create --domain magnum --password $MAGNUM_PASS magnum_domain_admin

echo "Присваивание пользователю magnum_domain_admin роли admin в домене magnum"

openstack role add --domain magnum --user-domain magnum --user magnum_domain_admin admin 

echo "Создание постоянного тома lvm-magnum"

openstack volume type create lvm-magnum --public

echo "Создание БД для сервиса Magnum"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE magnum;"

echo "Выдача прав на работу с БД пользователю magnum"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON magnum.* TO 'magnum'@'localhost' IDENTIFIED BY '$MAGNUM_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON magnum.* TO 'magnum'@'%' IDENTIFIED BY '$MAGNUM_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя RabbitMQ для сервиса Magnum"

rabbitmqctl add_user magnum $MAGNUM_PASS

echo "Выдача созданному пользователю RabbitMQ всех разрешений"

rabbitmqctl set_permissions magnum ".*" ".*" ".*"

echo "Установка служб необходимых для работы сервиса Magnum"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install python3-magnumclient
}



function magnum_network_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Magnum\033[0m"

echo "Установка служб необходимых для работы сервиса Magnum"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-magnum-api openstack-magnum-conductor python3-magnumclient

echo "Редактирование конфига /etc/magnum/magnum.conf"

crudini --set /etc/magnum/magnum.conf DEFAULT transport_url rabbit://magnum:$MAGNUM_PASS@$NOVA_HOSTNAME
crudini --set /etc/magnum/magnum.conf DEFAULT log_dir /var/log/magnum
crudini --set /etc/magnum/magnum.conf api host 0.0.0.0
crudini --set /etc/magnum/magnum.conf api enabled_ssl false
crudini --set /etc/magnum/magnum.conf database connection mysql+pymysql://magnum:$MAGNUM_PASS@$NOVA_HOSTNAME/magnum
crudini --set /etc/magnum/magnum.conf certificates cert_manager_type barbican
crudini --set /etc/magnum/magnum.conf cinder default_docker_volume_type lvm-magnum
crudini --set /etc/magnum/magnum.conf cinder_client region_name RegionOne
crudini --set /etc/magnum/magnum.conf magnum_client region_name RegionOne

crudini --set /etc/magnum/magnum.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/magnum/magnum.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/magnum/magnum.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/magnum/magnum.conf keystone_authtoken auth_type password
crudini --set /etc/magnum/magnum.conf keystone_authtoken auth_version v3
crudini --set /etc/magnum/magnum.conf keystone_authtoken project_domain_name default
crudini --set /etc/magnum/magnum.conf keystone_authtoken user_domain_name default
crudini --set /etc/magnum/magnum.conf keystone_authtoken project_name service
crudini --set /etc/magnum/magnum.conf keystone_authtoken username magnum
crudini --set /etc/magnum/magnum.conf keystone_authtoken password $MAGNUM_PASS
crudini --set /etc/magnum/magnum.conf keystone_authtoken admin_user magnum
crudini --set /etc/magnum/magnum.conf keystone_authtoken admin_password $MAGNUM_PASS
crudini --set /etc/magnum/magnum.conf keystone_authtoken admin_tenant_name service

crudini --set /etc/magnum/magnum.conf oslo_policy enforce_scope false
crudini --set /etc/magnum/magnum.conf oslo_policy enforce_new_defaults false
crudini --set /etc/magnum/magnum.conf oslo_policy policy_file /etc/magnum/policy.json
crudini --set /etc/magnum/magnum.conf oslo_messaging_notifications driver messagingv2
crudini --set /etc/magnum/magnum.conf trust trustee_domain_name magnum
crudini --set /etc/magnum/magnum.conf trust trustee_domain_admin_name magnum_domain_admin
crudini --set /etc/magnum/magnum.conf trust trustee_domain_admin_password $MAGNUM_PASS
crudini --set /etc/magnum/magnum.conf trust trustee_keystone_interface public

echo "Редактирование конфига /etc/magnum/policy.json"

cat << EOF > /etc/magnum/policy.json
{
    "context_is_admin": "role:admin",
    "admin_or_owner": "is_admin:True or project_id:%(project_id)s",
    "admin_api": "rule:context_is_admin",
    "admin_or_user": "is_admin:True or user_id:%(user_id)s",
    "cluster_user": "user_id:%(trustee_user_id)s",
    "deny_cluster_user": "not domain_id:%(trustee_domain_id)s",
    "bay:create": "rule:deny_cluster_user",
    "bay:delete": "rule:deny_cluster_user",
    "bay:detail": "rule:deny_cluster_user",
    "bay:get": "rule:deny_cluster_user",
    "bay:get_all": "rule:deny_cluster_user",
    "bay:update": "rule:deny_cluster_user",
    "baymodel:create": "rule:deny_cluster_user",
    "baymodel:delete": "rule:deny_cluster_user",
    "baymodel:detail": "rule:deny_cluster_user",
    "baymodel:get": "rule:deny_cluster_user",
    "baymodel:get_all": "rule:deny_cluster_user",
    "baymodel:update": "rule:deny_cluster_user",
    "baymodel:publish": "rule:admin_api",
    "certificate:create": "rule:admin_or_user or rule:cluster_user",
    "certificate:get": "rule:admin_or_user or rule:cluster_user",
    "certificate:rotate_ca": "rule:admin_or_owner",
    "cluster:create": "rule:deny_cluster_user",
    "cluster:delete": "rule:deny_cluster_user",
    "cluster:delete_all_projects": "rule:admin_api",
    "cluster:detail": "rule:deny_cluster_user",
    "cluster:detail_all_projects": "rule:admin_api",
    "cluster:get": "rule:deny_cluster_user",
    "cluster:get_one_all_projects": "rule:admin_api",
    "cluster:get_all": "rule:deny_cluster_user",
    "cluster:get_all_all_projects": "rule:admin_api",
    "cluster:update": "rule:deny_cluster_user",
    "cluster:update_health_status": "rule:admin_or_user or rule:cluster_user",
    "cluster:update_all_projects": "rule:admin_api",
    "cluster:resize": "rule:deny_cluster_user",
    "cluster:upgrade": "rule:deny_cluster_user",
    "cluster:upgrade_all_projects": "rule:admin_api",
    "clustertemplate:create": "rule:deny_cluster_user",
    "clustertemplate:delete": "rule:admin_or_owner",
    "clustertemplate:delete_all_projects": "rule:admin_api",
    "clustertemplate:detail_all_projects": "rule:admin_api",
    "clustertemplate:detail": "rule:deny_cluster_user",
    "clustertemplate:get": "rule:deny_cluster_user",
    "clustertemplate:get_one_all_projects": "rule:admin_api",
    "clustertemplate:get_all": "rule:deny_cluster_user",
    "clustertemplate:get_all_all_projects": "rule:admin_api",
    "clustertemplate:update": "rule:admin_or_owner",
    "clustertemplate:update_all_projects": "rule:admin_api",
    "clustertemplate:publish": "rule:admin_api",
    "federation:create": "rule:deny_cluster_user",
    "federation:delete": "rule:deny_cluster_user",
    "federation:detail": "rule:deny_cluster_user",
    "federation:get": "rule:deny_cluster_user",
    "federation:get_all": "rule:deny_cluster_user",
    "federation:update": "rule:deny_cluster_user",
    "magnum-service:get_all": "rule:admin_api",
    "quota:create": "rule:admin_api",
    "quota:delete": "rule:admin_api",
    "quota:get": "rule:admin_or_owner",
    "quota:get_all": "rule:admin_api",
    "quota:update": "rule:admin_api",
    "stats:get_all": "rule:admin_or_owner",
    "nodegroup:get": "rule:admin_or_owner",
    "nodegroup:get_all": "rule:admin_or_owner",
    "nodegroup:get_all_all_projects": "rule:admin_api",
    "nodegroup:get_one_all_projects": "rule:admin_api",
    "nodegroup:create": "rule:admin_or_owner",
    "nodegroup:delete": "rule:admin_or_owner",
    "nodegroup:update": "rule:admin_or_owner"
}
EOF
chmod 640 /etc/magnum/{magnum.conf,policy.json}
chgrp magnum /etc/magnum/{magnum.conf,policy.json}
mkdir /var/lib/magnum/tmp
chown magnum /var/lib/magnum/tmp

echo "Инициализация БД magnum"

su -s /bin/bash magnum -c "magnum-db-manage upgrade"

echo "Добавление Cinder в исключения firewall"

firewall-cmd --add-port=9511/tcp
firewall-cmd --runtime-to-permanent

echo "Запуск openstack-magnum-api и openstack-magnum-conductor"

systemctl enable --now openstack-magnum-api
systemctl enable --now openstack-magnum-conductor
}



function rally_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Rally\033[0m"

echo "Создание БД для сервиса Rally"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE rally;"

echo "Выдача прав на работу с БД пользователю rally"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON rally.* TO 'rally'@'localhost' IDENTIFIED BY '$RALLY_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON rally.* TO 'rally'@'%' IDENTIFIED BY '$RALLY_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Установка служб необходимых для работы сервиса Rally"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-rally openstack-rally-plugins python3-fixtures

echo "Редактирование конфига /etc/rally/rally.conf"

crudini --set /etc/rally/rally.conf DEFAULT log_file rally.log
crudini --set /etc/rally/rally.conf DEFAULT log_dir /var/log/rally
crudini --set /etc/rally/rally.conf database connection mysql+pymysql://rally:$RALLY_PASS@$NOVA_HOSTNAME/rally
mkdir /var/log/rally

echo "Инициализация БД rally"

 rally db create

echo "Заполнение переменных необходимых для проведения бенчмарков"

rally deployment create --fromenv --name=my-cloud
source ~/.rally/openrc

echo "Создание тестового бенчмарка по созданию и удалению ВМ в кластере (boot-and-delete.json)"

cat << EOF > boot-and-delete.json
{
  "NovaServers.boot_and_delete_server": [
    {
      "args": {
        "flavor": {
          "name": "m1.small"
        },
        "image": {
          "name": "Cirros"
        },
        "force_delete": false
      },
      "runner": {
        "type": "constant",
        "times": 10,
        "concurrency": 2
      },
      "context": {}
    }
  ]
}
EOF
}



function kitty_controller_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА CloudKitty\033[0m"

echo "Создание пользователя cloudkitty"

source ~/keystonerc_adm
openstack user create --domain default --project service --password $KITTY_PASS cloudkitty

echo "Присваивание пользователю cloudkitty роли admin в проекте serivce"

openstack role add --project service --user cloudkitty admin 

echo "Создание роли rating"

openstack role create rating

echo "Создание сервиса cloudkitty"

openstack service create --name cloudkitty --description "Rating Service" rating

echo "Создание точек входа в сервисы cloudkitty"

openstack endpoint create --region RegionOne rating public http://$KITTY_HOSTNAME:8889
openstack endpoint create --region RegionOne rating internal http://$KITTY_HOSTNAME:8889
openstack endpoint create --region RegionOne rating admin http://$KITTY_HOSTNAME:8889

echo "Создание БД для сервиса CloudKitty"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE cloudkitty;"

echo "Выдача прав на работу с БД пользователю cloudkitty"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON cloudkitty.* TO 'cloudkitty'@'localhost' IDENTIFIED BY '$KITTY_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON cloudkitty.* TO 'cloudkitty'@'%' IDENTIFIED BY '$KITTY_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя RabbitMQ для сервиса CloudKitty"

rabbitmqctl add_user cloudkitty $KITTY_PASS

echo "Выдача созданному пользователю RabbitMQ всех разрешений"

rabbitmqctl set_permissions cloudkitty ".*" ".*" ".*"

echo "Установка служб необходимых для работы сервиса CloudKitty"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install python3-cloudkittyclient 
}



function kitty_network_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА CloudKitty\033[0m"

echo "Установка служб необходимых для работы сервиса CloudKitty"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-cloudkitty-api openstack-cloudkitty-processor python3-cloudkittyclient httpd

echo "Редактирование конфига /etc/cloudkitty/cloudkitty.conf"

crudini --set /etc/cloudkitty/cloudkitty.conf DEFAULT transport_url rabbit://cloudkitty:$KITTY_PASS@$NOVA_HOSTNAME
crudini --set /etc/cloudkitty/cloudkitty.conf DEFAULT auth_strategy keystone
crudini --set /etc/cloudkitty/cloudkitty.conf DEFAULT log_dir /var/log/cloudkitty
crudini --set /etc/cloudkitty/cloudkitty.conf collect collector gnocchi
crudini --set /etc/cloudkitty/cloudkitty.conf collect metrics_conf /etc/cloudkitty/metrics.yml
crudini --set /etc/cloudkitty/cloudkitty.conf collector_gnocchi auth_section keystone_authtoken
crudini --set /etc/cloudkitty/cloudkitty.conf collector_gnocchi region_name RegionOne
crudini --set /etc/cloudkitty/cloudkitty.conf database connection mysql+pymysql://cloudkitty:$KITTY_PASS@$NOVA_HOSTNAME/cloudkitty
crudini --set /etc/cloudkitty/cloudkitty.conf collector_gnocchi region_name RegionOne
crudini --set /etc/cloudkitty/cloudkitty.conf fetcher backend gnocchi
crudini --set /etc/cloudkitty/cloudkitty.conf fetcher_gnocchi auth_section keystone_authtoken
crudini --set /etc/cloudkitty/cloudkitty.conf fetcher_gnocchi region_name RegionOne
crudini --set /etc/cloudkitty/cloudkitty.conf fetcher_keystone keystone_version 3
crudini --set /etc/cloudkitty/cloudkitty.conf fetcher_keystone auth_section keystone_authtoken
crudini --set /etc/cloudkitty/cloudkitty.conf fetcher_keystone region_name RegionOne
crudini --set /etc/cloudkitty/cloudkitty.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/cloudkitty/cloudkitty.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/cloudkitty/cloudkitty.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/cloudkitty/cloudkitty.conf keystone_authtoken auth_type password
crudini --set /etc/cloudkitty/cloudkitty.conf keystone_authtoken project_domain_name default
crudini --set /etc/cloudkitty/cloudkitty.conf keystone_authtoken user_domain_name default
crudini --set /etc/cloudkitty/cloudkitty.conf keystone_authtoken project_name service
crudini --set /etc/cloudkitty/cloudkitty.conf keystone_authtoken username cloudkitty
crudini --set /etc/cloudkitty/cloudkitty.conf keystone_authtoken password $KITTY_PASS
crudini --set /etc/cloudkitty/cloudkitty.conf keystone_authtoken region_name RegionOne
crudini --set /etc/cloudkitty/cloudkitty.conf oslo_messaging_notifications driver messagingv2
crudini --set /etc/cloudkitty/cloudkitty.conf oslo_messaging_notifications transport_url rabbit://cloudkitty:$KITTY_PASS@$NOVA_HOSTNAME
crudini --set /etc/cloudkitty/cloudkitty.conf storage backend sqlalchemy
crudini --set /etc/cloudkitty/cloudkitty.conf storage version 1
crudini --set /etc/cloudkitty/cloudkitty.conf orchestrator coordination_url mysql://cloudkitty:$KITTY_PASS@$NOVA_HOSTNAME/cloudkitty

echo "Редактирование конфига /etc/httpd/conf.d/10-cloudkitty_wsgi.conf"

cat << EOF > /etc/httpd/conf.d/10-cloudkitty_wsgi.conf
Listen 8889
<VirtualHost *:8889>
    <Directory /usr/bin>
        AllowOverride None
        Require all granted
    </Directory>

    CustomLog /var/log/httpd/cloudkitty_wsgi_access.log combined
    ErrorLog /var/log/httpd/cloudkitty_wsgi_error.log
    WSGIApplicationGroup %{GLOBAL}
    WSGIDaemonProcess cloudkitty display-name=cloudkitty_wsgi user=cloudkitty group=cloudkitty processes=6 threads=6
    WSGIProcessGroup cloudkitty
    WSGIScriptAlias / /usr/bin/cloudkitty-api
</VirtualHost>
EOF
pip3 install DateTimeRange
chmod 640 /etc/cloudkitty/metrics.yml
chgrp cloudkitty /etc/cloudkitty/metrics.yml

echo "Инициализация БД cloudkitty"

su -s /bin/bash cloudkitty -c "cloudkitty-dbsync upgrade"
su -s /bin/bash cloudkitty -c "cloudkitty-storage-init"

echo "Добавление CloudKitty в исключения firewall"

firewall-cmd --add-port=8889/tcp
firewall-cmd --runtime-to-permanent

echo "Запуск cloudkitty-processor"

systemctl enable --now cloudkitty-processor
}



function trove_controller_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Trove\033[0m"

echo "Создание пользователя trove"
	
source ~/keystonerc_adm
openstack user create --domain default --project service --password $TROVE_PASS trove

echo "Присваивание пользователю trove роли admin в проекте serivce"

openstack role add --project service --user trove admin 

echo "Создание сервиса trove"

openstack service create --name trove --description "Database Service" database

echo "Создание точек входа в сервисы trove"

openstack endpoint create --region RegionOne database public http://$NOVA_HOSTNAME:8779/v1.0/%\(tenant_id\)s
openstack endpoint create --region RegionOne database internal http://$NOVA_HOSTNAME:8779/v1.0/%\(tenant_id\)s
openstack endpoint create --region RegionOne database admin http://$NOVA_HOSTNAME:8779/v1.0/%\(tenant_id\)s

echo "Создание типа постоянного тома lvm-trove"

openstack volume type create lvm-trove --private 

echo "Создание БД для сервиса Trove"

mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE trove;"

echo "Выдача прав на работу с БД пользователю trove"

mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON trove.* TO 'trove'@'localhost' IDENTIFIED BY '$TROVE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON trove.* TO 'trove'@'%' IDENTIFIED BY '$TROVE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"

echo "Создание пользователя RabbitMQ для сервиса Trove"

rabbitmqctl add_user trove $TROVE_PASS

echo "Выдача созданному пользователю RabbitMQ всех разрешений"

rabbitmqctl set_permissions trove ".*" ".*" ".*"

echo "Установка служб необходимых для работы сервиса Trove"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install python3-troveclient
}



function trove_network_config() {

echo -e "\033[1mУСТАНОВКА И НАСТРОЙКА Trove\033[0m"

echo "Установка служб необходимых для работы сервиса Trove"

dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-trove-api openstack-trove-conductor openstack-trove-taskmanager python3-troveclient

echo "Редактирование конфига /etc/trove/trove.conf"

crudini --set /etc/trove/trove.conf DEFAULT log_dir /var/log/trove
crudini --set /etc/trove/trove.conf DEFAULT transport_url rabbit://trove:$TROVE_PASS@$NOVA_HOSTNAME
crudini --set /etc/trove/trove.conf DEFAULT control_exchange trove
crudini --set /etc/trove/trove.conf DEFAULT default_datastore mysql
crudini --set /etc/trove/trove.conf DEFAULT cinder_volume_type lvm-trove
crudini --set /etc/trove/trove.conf DEFAULT cloudinit_location /etc/trove/cloudinit
crudini --set /etc/trove/trove.conf database connection mysql+pymysql://trove:$TROVE_PASS@$NOVA_HOSTNAME/trove
crudini --set /etc/trove/trove.conf mariadb tcp_ports 3306,4444,4567,4568
crudini --set /etc/trove/trove.conf mysql tcp_ports 3306
crudini --set /etc/trove/trove.conf postgresql tcp_ports 5432
crudini --set /etc/trove/trove.conf redis tcp_ports 6379,16379
crudini --set /etc/trove/trove.conf keystone_authtoken www_authenticate_uri http://$NOVA_HOSTNAME:5000
crudini --set /etc/trove/trove.conf keystone_authtoken auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/trove/trove.conf keystone_authtoken memcached_servers $NOVA_HOSTNAME:11211
crudini --set /etc/trove/trove.conf keystone_authtoken auth_type password
crudini --set /etc/trove/trove.conf keystone_authtoken project_domain_name default
crudini --set /etc/trove/trove.conf keystone_authtoken user_domain_name default
crudini --set /etc/trove/trove.conf keystone_authtoken project_name service
crudini --set /etc/trove/trove.conf keystone_authtoken username trove
crudini --set /etc/trove/trove.conf keystone_authtoken password $TROVE_PASS
crudini --set /etc/trove/trove.conf service_credentials auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/trove/trove.conf service_credentials region_name RegionOne
crudini --set /etc/trove/trove.conf service_credentials project_domain_name default
crudini --set /etc/trove/trove.conf service_credentials user_domain_name default
crudini --set /etc/trove/trove.conf service_credentials project_name service
crudini --set /etc/trove/trove.conf service_credentials username trove
crudini --set /etc/trove/trove.conf service_credentials password $TROVE_PASS

echo "Редактирование конфига /etc/trove/trove-guestagent.conf"

crudini --set /etc/trove/trove-guestagent.conf DEFAULT log_dir /var/log/trove
crudini --set /etc/trove/trove-guestagent.confDEFAULT log_file trove-guestagent.log
crudini --set /etc/trove/trove-guestagent.confDEFAULT ignore_users os_admin
crudini --set /etc/trove/trove-guestagent.confDEFAULT control_exchange trove
crudini --set /etc/trove/trove-guestagent.confDEFAULT transport_url rabbit://trove:$TROVE_PASS@$NOVA_HOSTNAME
crudini --set /etc/trove/trove-guestagent.confDEFAULT use_syslog false
crudini --set /etc/trove/trove-guestagent.confservice_credentials auth_url http://$NOVA_HOSTNAME:5000
crudini --set /etc/trove/trove-guestagent.confservice_credentials region_name RegionOne
crudini --set /etc/trove/trove-guestagent.confservice_credentials project_domain_name default
crudini --set /etc/trove/trove-guestagent.confservice_credentials user_domain_name default
crudini --set /etc/trove/trove-guestagent.confservice_credentials project_name service
crudini --set /etc/trove/trove-guestagent.confservice_credentials username trove
crudini --set /etc/trove/trove-guestagent.confservice_credentials password $TROVE_PASS
chmod 640 /etc/trove/trove-guestagent.conf
chgrp trove /etc/trove/trove-guestagent.conf

echo "Инициализация БД trove"

su -s /bin/bash trove -c "trove-manage db_sync"

echo "Добавление NFS в исключения firewall"

firewall-cmd --add-port=8779/tcp
firewall-cmd --runtime-to-permanent

echo "Запуск openstack-trove-api, openstack-trove-taskmanager и openstack-trove-conductor"

systemctl enable --now openstack-trove-api
systemctl enable --now openstack-trove-taskmanager
systemctl enable --now openstack-trove-conductor
}
