#!/bin/bash

#============= ENV ==============
NEUTRON_PASS="${NEUTRON_PASS:-neutron}"
ADMIN_PASS="${ADMIN_PASS:-openstack}"
DB_PASS="${DB_PASS:-mariadb}"
RABBIT_PASS="${RABBIT_PASS:-rabbit}"
GLANCE_PASS="${GLANCE_PASS:-glance}"
KEYSTONE_PASS="${KEYSTONE_PASS:-keystone}"
CINDER_PASS="${CINDER_PASS:-cinder}"
NOVA_PASS="${NOVA_PASS:-nova}"
PLACEMENT_PASS="${PLACEMENT_PASS:-placement}"
METADATA_SECRET="${METADATA_SECRET:-openstack}"
HOSTNAME="${HOSTNAME:-controller.test.local}"
HOST_IP="$(ip -f inet addr show enp1s0 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')"
IFS=. read -r a b c <<< "$HOSTNAME"
DNS="$b.$c"
IFS=. read -r a b c d <<< "$HOST_IP"
HOST_NETWORK="$a.$b.$c.0"


#=============== INIT =================
echo "Проверка доступа в интернет"
PING=$(ping google.com -c 3 | grep "packet loss" | grep -Eo "[0-9]+%" | grep -Eo "[0-9]+")
if [ "$PING" -eq "0" ]; then
echo "Доступ в интернет имеется"
else
echo "У узла должен быть доступ в интренет (посмотрите гайд по созданию узла github.com/artemchikus/openbash/openstack-guide.md)"
exit 1
fi

echo "Проверка ресурса CPU"
CORES=$(cat /proc/cpuinfo | grep processor | wc -l)
if [ "$CORES" -ge "2" ]; then
echo "vCPUS достаточно"
else
echo "Для узла нужно как минимум 2 vCPUS (посмотрите гайд по созданию узла github.com/artemchikus/openbash/openstack-guide.md)"
exit 1
fi

echo "Проверка ресурса оперативной памяти"
RAM=$(cat /proc/meminfo | grep "MemTotal" | grep -Eo "[0-9]+")
RAM=$(($RAM / 1048576))
if [ "$RAM" -ge "7" ]; then
echo "RAM достаточно"
else
echo "Для узла нужно как минимум 8 GB RAM (посмотрите гайд по созданию узла github.com/artemchikus/openbash/openstack-guide.md)"
exit 1
fi

echo "Проверка наличия двух сетевых интерфейсов (enp1s0 и enp*s0)"
ETH=$(ip a | grep -E "enp[0-9]s0:" | wc -l)
if [ "$ETH" -ge "2" ]; then
echo "Оба сетевых интерфейса присутствуют"
else
echo "У узла должны быть два сетевых интерфейса (enp1s0 и enp*s0) (посмотрите гайд по созданию узла github.com/artemchikus/openbash/openstack-guide.md)"
exit 1
fi

echo "Проверка наличия отдельного диска (vdb) для lvm-группы сервиса Cinder"
LVM=$(lsblk /dev/vdb | wc -l)
if [ "$LVM" -ne "0" ]; then
echo "Узел поддерживает аппаратную виртуализацию"
else
echo "Для узла нужен дополнительный диск (vdb) для lvm-группы сервиса Cinder (посмотрите гайд по созданию узла github.com/artemchikus/openbash/openstack-guide.md)"
exit 1
fi

hostnamectl set-hostname $HOSTNAME
echo "$HOST_IP $HOSTNAME" >> /etc/hosts
sed -c -i 's/#allow 192.168.0.0\/16/allow '$HOST_NETWORK'\/24/' /etc/chrony.conf
systemctl restart chronyd
systemctl enable --now chronyd


#============== MARIADB ===============
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
mysql --user="root" --execute="ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_PASS';"


#============= RABBITMQ ===============
echo "RABBITMQ_NODENAME=rabbit@$HOSTNAME" >> /etc/rabbitmq/rabbitmq-env.conf
systemctl enable --now rabbitmq-server
rabbitmqctl set_cluster_name rabbit@$HOSTNAME
rabbitmqctl change_password guest $RABBIT_PASS


#============= KEYSTONE ===============
mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE keystone;"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"
crudini --set /etc/keystone/keystone.conf cache memcache_servers $HOSTNAME:11211
crudini --set /etc/keystone/keystone.conf database connection mysql+pymysql://keystone:$KEYSTONE_PASS@$HOSTNAME/keystone
su -s /bin/bash keystone -c "keystone-manage db_sync" 
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password $ADMIN_PASS --bootstrap-admin-url http://$HOSTNAME:5000/v3/ --bootstrap-internal-url http://$HOSTNAME:5000/v3/ --bootstrap-public-url http://$HOSTNAME:5000/v3/ --bootstrap-region-id RegionOne
echo "ServerName $HOSTNAME" >> /etc/httpd/conf/httpd.conf
systemctl enable --now httpd
{
echo "unset OS_USERNAME OS_PASSWORD OS_PROJECT_NAME OS_USER_DOMAIN_NAME OS_PROJECT_DOMAIN_NAME OS_AUTH_URL OS_IDENTITY_API_VERSION PS1 REQUESTS_CA_BUNDLE"
echo "export OS_USERNAME=admin"
echo "export OS_PASSWORD=$ADMIN_PASS"
echo "export OS_PROJECT_NAME=admin"
echo "export OS_USER_DOMAIN_NAME=default"
echo "export OS_PROJECT_DOMAIN_NAME=default"
echo "export OS_AUTH_URL=http://$HOSTNAME:5000"
echo "export OS_IDENTITY_API_VERSION=3"
echo "export OS_IMAGE_API_VERSION=2"
echo "export OS_VOLUME_API_VERSION=3"
echo "export PS1='[\u@\h \W(Openstack_Admin)]\$ '"
} > ~/keystonerc_adm
source ~/keystonerc_adm
openstack project create --domain default --description "Service Project" service


#============== GLANCE ================
source ~/keystonerc_adm
openstack user create --domain default --project service --password $GLANCE_PASS glance 
openstack role add --project service --user glance admin
openstack service create --name glance --description "Image Service" image
openstack endpoint create --region RegionOne image public http://$HOSTNAME:9292
openstack endpoint create --region RegionOne image internal http://$HOSTNAME:9292
openstack endpoint create --region RegionOne image admin http://$HOSTNAME:9292
mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE glance;"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"
rabbitmqctl add_user glance $GLANCE_PASS
rabbitmqctl set_permissions glance ".*" ".*" ".*"
crudini --set /etc/glance/glance-api.conf DEFAULT transport_url rabbit://glance:$GLANCE_PASS@$HOSTNAME
crudini --set /etc/glance/glance-api.conf database connection mysql+pymysql://glance:$GLANCE_PASS@$HOSTNAME/glance
crudini --set /etc/glance/glance-api.conf keystone_authtoken www_authenticate_uri http://$HOSTNAME:5000
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_url http://$HOSTNAME:5000
crudini --set /etc/glance/glance-api.conf keystone_authtoken memcached_servers $HOSTNAME:11211
crudini --set /etc/glance/glance-api.conf keystone_authtoken password $GLANCE_PASS
su -s /bin/bash glance -c "glance-manage db_sync"
systemctl enable --now openstack-glance-api


#=============== NOVA =================
source ~/keystonerc_adm
openstack user create --domain default --project service --password $NOVA_PASS nova
openstack role add --project service --user nova admin 
openstack user create --domain default --project service --password $PLACEMENT_PASS placement
openstack role add --project service --user placement admin 
openstack service create --name nova --description "Compute Service" compute
openstack service create --name placement --description "Compute Placement Service" placement
openstack endpoint create --region RegionOne compute public http://$HOSTNAME:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://$HOSTNAME:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://$HOSTNAME:8774/v2.1
openstack endpoint create --region RegionOne placement public http://$HOSTNAME:8778
openstack endpoint create --region RegionOne placement internal http://$HOSTNAME:8778
openstack endpoint create --region RegionOne placement admin http://$HOSTNAME:8778
mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE nova_api;"
mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE nova;"
mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE nova_cell0;"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"
mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE placement;"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PLACEMENT_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PLACEMENT_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"
rabbitmqctl add_user nova $NOVA_PASS
rabbitmqctl set_permissions nova ".*" ".*" ".*"
crudini --set /etc/nova/nova.conf DEFAULT my_ip $HOST_IP
crudini --set /etc/nova/nova.conf DEFAULT transport_url rabbit://nova:$NOVA_PASS@$HOSTNAME
crudini --set /etc/nova/nova.conf vnc novncproxy_base_url http://$HOSTNAME:6080/vnc_auto.html
crudini --set /etc/nova/nova.conf vnc server_listen $HOST_IP
crudini --set /etc/nova/nova.conf vnc server_proxyclient_address $HOST_IP
crudini --set /etc/nova/nova.conf glance api_servers http://$HOSTNAME:9292
crudini --set /etc/nova/nova.conf api_database connection mysql+pymysql://nova:$NOVA_PASS@$HOSTNAME/nova_api
crudini --set /etc/nova/nova.conf database connection mysql+pymysql://nova:$NOVA_PASS@$HOSTNAME/nova
crudini --set /etc/nova/nova.conf keystone_authtoken www_authenticate_uri http://$HOSTNAME:5000
crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://$HOSTNAME:5000
crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers $HOSTNAME:11211
crudini --set /etc/nova/nova.conf keystone_authtoken password $NOVA_PASS
crudini --set /etc/nova/nova.conf placement auth_url http://$HOSTNAME:5000
crudini --set /etc/nova/nova.conf placement password $PLACEMENT_PASS
crudini --set /etc/placement/placement.conf keystone_authtoken www_authenticate_uri http://$HOSTNAME:5000
crudini --set /etc/placement/placement.conf keystone_authtoken auth_url http://$HOSTNAME:5000
crudini --set /etc/placement/placement.conf keystone_authtoken memcached_servers $HOSTNAME:11211
crudini --set /etc/placement/placement.conf keystone_authtoken password $PLACEMENT_PASS
crudini --set /etc/placement/placement.conf placement_database connection mysql+pymysql://placement:$PLACEMENT_PASS@$HOSTNAME/placement
su -s /bin/bash placement -c "placement-manage db sync" 
su -s /bin/bash nova -c "nova-manage api_db sync" 
su -s /bin/bash nova -c "nova-manage cell_v2 map_cell0"
su -s /bin/bash nova -c "nova-manage db sync"
su -s /bin/bash nova -c "nova-manage cell_v2 create_cell --name cell1"
systemctl restart httpd
systemctl enable --now openstack-nova-api
systemctl enable --now openstack-nova-conductor
systemctl enable --now openstack-nova-scheduler
systemctl enable --now openstack-nova-novncproxy
systemctl enable --now openstack-nova-compute
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova


#============== NEUTRON ===============
source ~/keystonerc_adm
openstack user create --domain default --project service --password $NEUTRON_PASS neutron
openstack role add --project service --user neutron admin 
openstack service create --name neutron --description "Networking Service" network
openstack endpoint create --region RegionOne network public http://$HOSTNAME:9696
openstack endpoint create --region RegionOne network internal http://$HOSTNAME:9696
openstack endpoint create --region RegionOne network admin http://$HOSTNAME:9696
mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE neutron;"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"
rabbitmqctl add_user neutron $NEUTRON_PASS
rabbitmqctl set_permissions neutron ".*" ".*" ".*"
crudini --set /etc/nova/nova.conf neutron auth_url http://$HOSTNAME:5000
crudini --set /etc/nova/nova.conf neutron password $NEUTRON_PASS
crudini --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret $METADATA_SECRET
systemctl restart openstack-nova-api
crudini --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://neutron:$NEUTRON_PASS@$HOSTNAME
crudini --set /etc/neutron/neutron.conf keystone_authtoken www_authenticate_uri http://$HOSTNAME:5000
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://$HOSTNAME:5000
crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers $HOSTNAME:11211
crudini --set /etc/neutron/neutron.conf keystone_authtoken password $NEUTRON_PASS
crudini --set /etc/neutron/neutron.conf database connection mysql+pymysql://neutron:$NEUTRON_PASS@$HOSTNAME/neutron
crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp
crudini --set /etc/neutron/neutron.conf nova auth_url http://$HOSTNAME:5000
crudini --set /etc/neutron/neutron.conf nova password $NOVA_PASS
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_nb_connection tcp:$HOST_IP:6641
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_sb_connection tcp:$HOST_IP:6642
crudini --set /etc/neutron/neutron_ovn_metadata_agent.ini DEFAULT nova_metadata_host $HOSTNAME
crudini --set /etc/neutron/neutron_ovn_metadata_agent.ini DEFAULT metadata_proxy_shared_secret $METADATA_SECRET
crudini --set /etc/neutron/neutron_ovn_metadata_agent.ini ovs ovsdb_connection tcp:127.0.0.1:6640
crudini --set /etc/neutron/neutron_ovn_metadata_agent.ini ovn ovn_sb_connection tcp:$HOST_IP:6642
su -s /bin/bash neutron -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugin.ini upgrade head"
systemctl enable --now openvswitch
systemctl enable --now ovn-controller
ovs-vsctl add-br br-int
systemctl enable --now ovn-northd
ovn-nbctl set-connection ptcp:6641:$HOST_IP -- set connection . inactivity_probe=60000
ovn-sbctl set-connection ptcp:6642:$HOST_IP -- set connection . inactivity_probe=60000 
ovs-vsctl set open . external-ids:ovn-remote=tcp:$HOST_IP:6642 
ovs-vsctl set open . external-ids:ovn-encap-type=geneve
ovs-vsctl set open . external-ids:ovn-encap-ip=$HOST_IP
ovs-vsctl add-br br-ex
enp=$(ip a | grep -E "enp[0-9]s0:" | grep -Eo "enp[2-9]s0")
ovs-vsctl add-port br-ex $enp
ovs-vsctl set open . external-ids:ovn-bridge-mappings=external:br-ex
systemctl restart openstack-nova-compute
systemctl enable --now neutron-ovn-metadata-agent 
systemctl enable --now neutron-server


#============== CINDER ================
source ~/keystonerc_adm
openstack user create --domain default --project service --password $CINDER_PASS cinder
openstack role add --project service --user cinder admin 
openstack service create --name cinderv3 --description "Block Storage" volumev3
openstack endpoint create --region RegionOne volumev3 public http://$HOSTNAME:8776/v3
openstack endpoint create --region RegionOne volumev3 internal http://$HOSTNAME:8776/v3
openstack endpoint create --region RegionOne volumev3 admin http://$HOSTNAME:8776/v3
mysql --user="root" --password="$DB_PASS" --execute="CREATE DATABASE cinder;"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$CINDER_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_PASS';"
mysql --user="root" --password="$DB_PASS" --execute="FLUSH PRIVILEGES;"
rabbitmqctl add_user cinder $CINDER_PASS
rabbitmqctl set_permissions cinder ".*" ".*" ".*"
crudini --set /etc/cinder/cinder.conf DEFAULT transport_url rabbit://cinder:$CINDER_PASS@$HOSTNAME
crudini --set /etc/cinder/cinder.conf DEFAULT my_ip $HOST_IP
crudini --set /etc/cinder/cinder.conf DEFAULT glance_api_servers http://$HOSTNAME:9292
crudini --set /etc/cinder/cinder.conf lvm target_ip_address $HOST_IP
crudini --set /etc/cinder/cinder.conf database connection mysql+pymysql://cinder:$CINDER_PASS@$HOSTNAME/cinder
crudini --set /etc/cinder/cinder.conf keystone_authtoken www_authenticate_uri http://$HOSTNAME:5000
crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_url http://$HOSTNAME:5000
crudini --set /etc/cinder/cinder.conf keystone_authtoken memcached_servers $HOSTNAME:11211
crudini --set /etc/cinder/cinder.conf keystone_authtoken password $CINDER_PASS
su -s /bin/bash cinder -c "cinder-manage db sync"
systemctl enable --now openstack-cinder-api
systemctl enable --now openstack-cinder-scheduler
vgcreate cinder-volumes /dev/vdb
sed -c -i 's/#Domain = local.domain.edu/Domain = '$DNS'/' /etc/idmapd.conf
systemctl enable --now openstack-cinder-volume
systemctl restart openstack-nova-compute 