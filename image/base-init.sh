#!/bin/bash

#=============== INIT =================
dnf -y install chrony
sed -c -i 's/pool 2.centos.pool.ntp.org iburst/pool 0.pool.ntp.org iburst/' /etc/chrony.conf
firewall-cmd --add-service=ntp
firewall-cmd --runtime-to-permanent
dnf -y install centos-release-openstack-zed
sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/CentOS-OpenStack-zed.repo
dnf -y install epel-release epel-next-release
sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/epel.repo
sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/epel-next.repo
dnf --enablerepo=centos-openstack-zed -y upgrade
dnf --enablerepo=epel,epel-next -y install crudini


#============== MARIADB ===============
dnf -y install mariadb-server
{
echo "[mysqld]"
echo "character-set-server = utf8mb4"
echo "[client]"
echo "default-character-set = utf8mb4"
} > /etc/my.cnf.d/charset.cnf
firewall-cmd --add-service=mysql 
firewall-cmd --runtime-to-permanent 
systemctl enable --now mariadb


#============= RABBITMQ ===============
dnf -y install rabbitmq-server
crudini --ini-options=nospace --set /etc/my.cnf.d/mariadb-server.cnf mysqld max_connections 1024
touch /etc/rabbitmq/rabbitmq-env.conf
echo "RABBITMQ_USE_LONGNAME=true" > /etc/rabbitmq/rabbitmq-env.conf
chown rabbitmq:rabbitmq /etc/rabbitmq/rabbitmq-env.conf
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
firewall-cmd --add-port=5672/tcp
firewall-cmd --runtime-to-permanent 


#============= MEMCACHED ==============
dnf -y install memcached
crudini --ini-options=nospace --set /etc/sysconfig/memcached "" OPTIONS "\"-l 0.0.0.0,::\""
systemctl enable --now memcached
firewall-cmd --add-service=memcache	
firewall-cmd --runtime-to-permanent


#============= KEYSTONE ===============
dnf --enablerepo=centos-openstack-zed,epel -y install openstack-keystone python3-openstackclient httpd python3-mod_wsgi python3-oauth2client
crudini --set /etc/keystone/keystone.conf token provider fernet
ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
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
firewall-cmd --add-port=5000/tcp
firewall-cmd --runtime-to-permanent


#============== GLANCE ================
dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-glance
crudini --set /etc/glance/glance-api.conf DEFAULT log_dir /var/log/glance
crudini --set /etc/glance/glance-api.conf glance_store stores file,http
crudini --set /etc/glance/glance-api.conf glance_store default_store file
crudini --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir /var/lib/glance/images/
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_type password
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_domain_name default
crudini --set /etc/glance/glance-api.conf keystone_authtoken user_domain_name default
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_name service
crudini --set /etc/glance/glance-api.conf keystone_authtoken username glance
crudini --set /etc/glance/glance-api.conf paste_deploy flavor keystone
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
firewall-cmd --add-port=9292/tcp
firewall-cmd --runtime-to-permanent 


#=============== NOVA =================
dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-nova openstack-placement-api 
crudini --set /etc/nova/nova.conf DEFAULT compute_driver libvirt.LibvirtDriver
crudini --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
crudini --set /etc/nova/nova.conf DEFAULT log_dir /var/log/nova
crudini --set /etc/nova/nova.conf DEFAULT state_path /var/lib/nova
crudini --set /etc/nova/nova.conf DEFAULT instances_path /var/lib/nova/instances
crudini --set /etc/nova/nova.conf api auth_strategy keystone
crudini --set /etc/nova/nova.conf vnc enabled true
crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp
crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name default
crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name default
crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
crudini --set /etc/nova/nova.conf keystone_authtoken username nova
crudini --set /etc/nova/nova.conf placement region_name RegionOne
crudini --set /etc/nova/nova.conf placement auth_type password
crudini --set /etc/nova/nova.conf placement project_domain_name default
crudini --set /etc/nova/nova.conf placement user_domain_name default
crudini --set /etc/nova/nova.conf placement project_name service
crudini --set /etc/nova/nova.conf placement username placement
crudini --set /etc/nova/nova.conf wsgi api_paste_config /etc/nova/api-paste.ini
crudini --set /etc/placement/placement.conf DEFAULT debug false 
crudini --set /etc/placement/placement.conf api auth_strategy keystone
crudini --set /etc/placement/placement.conf keystone_authtoken auth_type password
crudini --set /etc/placement/placement.conf keystone_authtoken project_domain_name default
crudini --set /etc/placement/placement.conf keystone_authtoken user_domain_name default
crudini --set /etc/placement/placement.conf keystone_authtoken project_name service
crudini --set /etc/placement/placement.conf keystone_authtoken username placement
sed -i -c '/\/VirtualHost/i \
  <Directory /usr/bin>\
    Require all granted\
  </Directory>' /etc/httpd/conf.d/00-placement-api.conf 
chown placement. /var/log/placement/
dnf --enablerepo=centos-openstack-zed -y install openstack-selinux
semanage port -a -t http_port_t -p tcp 8778
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
firewall-cmd --add-port={6080/tcp,6081/tcp,6082/tcp,8774/tcp,8775/tcp,8778/tcp}
firewall-cmd --runtime-to-permanent
dnf -y install qemu-kvm libvirt virt-install
systemctl enable --now libvirtd
dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-nova-compute
firewall-cmd --add-port=5900-5999/tcp
firewall-cmd --runtime-to-permanent


#============== NEUTRON ===============
crudini --set /etc/nova/nova.conf DEFAULT vif_plugging_is_fatal True
crudini --set /etc/nova/nova.conf DEFAULT vif_plugging_timeout 300
crudini --set /etc/nova/nova.conf neutron auth_type password
crudini --set /etc/nova/nova.conf neutron project_domain_name default
crudini --set /etc/nova/nova.conf neutron user_domain_name default
crudini --set /etc/nova/nova.conf neutron region_name RegionOne
crudini --set /etc/nova/nova.conf neutron project_name service
crudini --set /etc/nova/nova.conf neutron username neutron
crudini --set /etc/nova/nova.conf neutron service_metadata_proxy true
dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-neutron openstack-neutron-ml2 ovn-2021-central openstack-neutron-ovn-metadata-agent ovn-2021-host 
crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins ovn-router
crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips true
crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes true
crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes true
crudini --set /etc/neutron/neutron.conf DEFAULT state_path /var/lib/neutron
crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name default
crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name default
crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp
crudini --set /etc/neutron/neutron.conf nova auth_type password
crudini --set /etc/neutron/neutron.conf nova project_domain_name default
crudini --set /etc/neutron/neutron.conf nova user_domain_name default
crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
crudini --set /etc/neutron/neutron.conf nova project_name service
crudini --set /etc/neutron/neutron.conf nova username nova
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini DEFAULT debug false
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat,geneve
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types geneve
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers ovn
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 overlay_ip_version 4
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks '*'
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_geneve vni_ranges 1:65536
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_geneve max_header_size 38
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group true
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_l3_scheduler leastloaded
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_metadata_enabled true
crudini --set /etc/neutron/neutron_ovn_metadata_agent.ini agent root_helper "sudo neutron-rootwrap /etc/neutron/rootwrap.conf"
sed -c -i "s/OPTIONS=\"\"/OPTIONS=\"--ovsdb-server-options='--remote=ptcp:6640:127.0.0.1'\"/g" /etc/sysconfig/openvswitch
ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
setsebool -P neutron_can_network on
setsebool -P haproxy_connect_any on 
setsebool -P daemons_enable_cluster_mode on
cat << EOF > ovsofctl.te
module ovsofctl 1.0;

require {
        type neutron_t;
        type neutron_exec_t;
        type dnsmasq_t;
        type openvswitch_load_module_t;
        type tracefs_t;
        type var_run_t;
        type openvswitch_t;
        type ovsdb_port_t;
        type kdumpctl_exec_t;
        type devicekit_exec_t;
        type lsmd_exec_t;
        type lsmd_plugin_exec_t;
        type locate_exec_t;
        type glance_scrubber_exec_t;
        type gpg_agent_exec_t;
        type mount_exec_t;
        type rsync_exec_t;
        type journalctl_exec_t;
        type virt_qemu_ga_exec_t;
        type httpd_config_t;
        type chfn_exec_t;
        type glance_api_exec_t;
        type ssh_exec_t;
        type ssh_agent_exec_t;
        type systemd_hwdb_exec_t;
        type checkpolicy_exec_t;
        type chronyc_exec_t;
        type groupadd_exec_t;
        type loadkeys_exec_t;
        type fusermount_exec_t;
        type dmesg_exec_t;
        type rpmdb_exec_t;
        type memcached_exec_t;
        type conmon_exec_t;
        type systemd_tmpfiles_exec_t;
        type passwd_exec_t;
        type ssh_keygen_exec_t;
        type NetworkManager_exec_t;
        type su_exec_t;
        type dbusd_exec_t;
        type numad_exec_t;
        type container_runtime_exec_t;
        type ping_exec_t;
        type rpcbind_exec_t;
        type virtd_exec_t;
        type policykit_auth_exec_t;
        type systemd_systemctl_exec_t;
        type plymouth_exec_t;
        type keepalived_exec_t;
        type mandb_exec_t;
        type systemd_passwd_agent_exec_t;
        type traceroute_exec_t;
        type fsadm_exec_t;
        type thumb_exec_t;
        type mysqld_exec_t;
        type nova_exec_t;
        type crontab_exec_t;
        type swtpm_exec_t;
        type virsh_exec_t;
        type mysqld_safe_exec_t;
        type systemd_notify_exec_t;
        type vlock_exec_t;
        type gpg_exec_t;
        type login_exec_t;
        type hostname_exec_t;
        type tmpfs_t;
        class sock_file write;
        class file { execute_no_trans create read write open link getattr unlink };
        class dir search;
        class tcp_socket name_bind;
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
allow neutron_t fsadm_exec_t:file getattr;
allow neutron_t fusermount_exec_t:file getattr;
allow neutron_t glance_api_exec_t:file getattr;
allow neutron_t glance_scrubber_exec_t:file getattr;
allow neutron_t gpg_agent_exec_t:file getattr;
allow neutron_t gpg_exec_t:file getattr;
allow neutron_t groupadd_exec_t:file getattr;
allow neutron_t hostname_exec_t:file getattr;
allow neutron_t httpd_config_t:dir search;
allow neutron_t journalctl_exec_t:file getattr;
allow neutron_t kdumpctl_exec_t:file getattr;
allow neutron_t keepalived_exec_t:file getattr;
allow neutron_t loadkeys_exec_t:file getattr;
allow neutron_t locate_exec_t:file getattr;
allow neutron_t login_exec_t:file getattr;
allow neutron_t lsmd_exec_t:file getattr;
allow neutron_t lsmd_plugin_exec_t:file getattr;
allow neutron_t mandb_exec_t:file getattr;
allow neutron_t memcached_exec_t:file getattr;
allow neutron_t mount_exec_t:file getattr;
allow neutron_t mysqld_exec_t:file getattr;
allow neutron_t mysqld_safe_exec_t:file getattr;
allow neutron_t nova_exec_t:file getattr;
allow neutron_t numad_exec_t:file getattr;
allow neutron_t passwd_exec_t:file getattr;
allow neutron_t ping_exec_t:file getattr;
allow neutron_t plymouth_exec_t:file getattr;
allow neutron_t policykit_auth_exec_t:file getattr;
allow neutron_t rpcbind_exec_t:file getattr;
allow neutron_t rpmdb_exec_t:file getattr;
allow neutron_t rsync_exec_t:file getattr;
allow neutron_t ssh_agent_exec_t:file getattr;
allow neutron_t ssh_exec_t:file getattr;
allow neutron_t ssh_keygen_exec_t:file getattr;
allow neutron_t su_exec_t:file getattr;
allow neutron_t swtpm_exec_t:file getattr;
allow neutron_t systemd_hwdb_exec_t:file getattr;
allow neutron_t systemd_notify_exec_t:file getattr;
allow neutron_t systemd_passwd_agent_exec_t:file getattr;
allow neutron_t systemd_systemctl_exec_t:file getattr;
allow neutron_t systemd_tmpfiles_exec_t:file getattr;
allow neutron_t thumb_exec_t:file getattr;
allow neutron_t traceroute_exec_t:file getattr;
allow neutron_t virsh_exec_t:file getattr;
allow neutron_t virt_qemu_ga_exec_t:file getattr;
allow neutron_t virtd_exec_t:file getattr;
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
firewall-cmd --add-port={9696/tcp,6641/tcp,6642/tcp}
firewall-cmd --runtime-to-permanent


#============== CINDER ================
dnf --enablerepo=centos-openstack-zed,epel,crb -y install openstack-cinder
crudini --set /etc/cinder/cinder.conf DEFAULT rootwrap_config /etc/cinder/rootwrap.conf
crudini --set /etc/cinder/cinder.conf DEFAULT api_paste_confg /etc/cinder/api-paste.ini
crudini --set /etc/cinder/cinder.conf DEFAULT enable_v3_api true
crudini --set /etc/cinder/cinder.conf DEFAULT state_path /var/lib/cinder
crudini --set /etc/cinder/cinder.conf DEFAULT auth_strategy keystone
crudini --set /etc/cinder/cinder.conf DEFAULT enabled_backends lvm
crudini --set /etc/cinder/cinder.conf lvm target_helper lioadm
crudini --set /etc/cinder/cinder.conf lvm target_protocol iscsi
crudini --set /etc/cinder/cinder.conf lvm volume_group cinder-volumes
crudini --set /etc/cinder/cinder.conf lvm volume_driver cinder.volume.drivers.lvm.LVMVolumeDriver
crudini --set /etc/cinder/cinder.conf lvm volumes_dir /var/lib/cinder/volumes
crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_type password
crudini --set /etc/cinder/cinder.conf keystone_authtoken project_domain_name default
crudini --set /etc/cinder/cinder.conf keystone_authtoken user_domain_name default
crudini --set /etc/cinder/cinder.conf keystone_authtoken project_name service
crudini --set /etc/cinder/cinder.conf keystone_authtoken username cinder
crudini --set /etc/cinder/cinder.conf oslo_concurrency lock_path /var/lib/cinder/tmp
semanage port -a -t http_port_t -p tcp 8776
firewall-cmd --add-port=8776/tcp
firewall-cmd --runtime-to-permanent
dnf --enablerepo=centos-openstack-zed,epel,crb -y install targetcli
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
firewall-cmd --add-service=iscsi-target
firewall-cmd --runtime-to-permanent
systemctl enable --now iscsid
systemctl enable --now target
crudini --set /etc/nova/nova.conf cinder os_region_name RegionOne