#!/bin/bash

secure=0

cert_file=/etc/pki/tls/certs/swift.crt
key_file=/etc/pki/tls/private/swift.key
multivol=0
http=https
port=443
ssl='True'
admin_tenant=admin
if [ $secure -eq 0 ]; then
	http=http
	port=8080
	ssl='False'
fi

##This is a document in progress, and may contain some errors or missing information.

##I am currently in the process of building an AWS Image with this installed.
##mysql root password will be: glusterkey

##This document assumes you already have GlusterFS with UFO installed, 3.3.1-11 or later, and are using the instructions here:

##  http://www.gluster.org/2012/09/howto-using-ufo-swift-a-quick-and-dirty-setup-guide/
yum install -y wget xfsprogs vim
wget http://repos.fedorapeople.org/repos/kkeithle/glusterfs/epel-glusterfs.repo -O /etc/yum.repos.d/glusterfs-epel.repo
yum install -y http://dl.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm

##Add the RDO Openstack Grizzly repos:
yum install -y http://rdo.fedorapeople.org/openstack/openstack-grizzly/rdo-release-grizzly-1.noarch.rpm

yum install -y glusterfs glusterfs-server glusterfs-fuse glusterfs-swift glusterfs-swift-account glusterfs-swift-container glusterfs-swift-object glusterfs-swift-proxy glusterfs-ufo
service start glusterd
cd /etc/swift
printf "\n\n\n\n\n\n\n" | openssl req -new -x509 -nodes -out $cert_file -keyout $key_file

mv swift.conf-gluster swift.conf
mv fs.conf-gluster fs.conf
mv proxy-server.conf-gluster proxy-server.conf
mv account-server/1.conf-gluster account-server/1.conf
mv container-server/1.conf-gluster container-server/1.conf
mv object-server/1.conf-gluster object-server/1.conf
rm {account,container,object}-server.conf

yum install -y openstack-utils 
openstack-config --set /etc/swift/proxy-server.conf DEFAULT bind_port $port
if [ $secure -eq 1 ]; then
	openstack-config --set /etc/swift/proxy-server.conf DEFAULT key_file $cert_key
	openstack-config --set /etc/swift/proxy-server.conf DEFAULT cert_file $cert_file
fi
openstack-config --set /etc/swift/proxy-server.conf filter:cache memcache_servers 127.0.0.1:11211

service memcached start


##These docs are largely derived from:

##  http://fedoraproject.org/wiki/Getting_started_with_OpenStack_on_Fedora_17#Initial_Keystone_setup
##  http://blog.jebpages.com/archives/fedora-17-openstack-and-gluster-3-3/


#Install Openstack-Keystone

yum install -y openstack-keystone python-keystoneclient

#Configure keystone

cat > keystonerc << _EOF
export ADMIN_TOKEN=$(openssl rand -hex 10)
export OS_USERNAME=admin
export OS_PASSWORD=$(openssl rand -hex 10)
export OS_TENANT_NAME=$admin_tenant
export OS_AUTH_URL=$http://127.0.0.1:5000/v2.0/
export SERVICE_ENDPOINT=$http://127.0.0.1:35357/v2.0/
export SERVICE_TOKEN=\$ADMIN_TOKEN
_EOF
. ./keystonerc
openstack-db --service keystone --init --yes --rootpw glusterkey

#Append the keystone configs to /etc/swift/proxy-server.conf

cat >> /etc/swift/proxy-server.conf << _EOM
[filter:keystone]
use = egg:swift#keystoneauth
operator_roles = admin, swiftoperator
  
[filter:authtoken]
paste.filter_factory = keystoneclient.middleware.auth_token:filter_factory
auth_port = 35357
auth_host = 127.0.0.1
auth_protocol = $http
_EOM

#Finish configuring both swift and keystone using the command-line tool:

openstack-config --set /etc/swift/proxy-server.conf filter:authtoken admin_token $ADMIN_TOKEN
openstack-config --set /etc/swift/proxy-server.conf filter:authtoken auth_token $ADMIN_TOKEN
openstack-config --set /etc/swift/proxy-server.conf DEFAULT log_name proxy_server
openstack-config --set /etc/swift/proxy-server.conf filter:authtoken signing_dir /etc/swift
openstack-config --set /etc/swift/proxy-server.conf pipeline:main pipeline "healthcheck cache authtoken keystone proxy-server"
  
openstack-config --set /etc/keystone/keystone.conf DEFAULT admin_token $ADMIN_TOKEN
openstack-config --set /etc/keystone/keystone.conf ssl enable $ssl
if [ $secure -eq 1 ]; then
	openstack-config --set /etc/keystone/keystone.conf ssl keyfile $cert_key
	openstack-config --set /etc/keystone/keystone.conf ssl certfile $cert_file
fi
openstack-config --set /etc/keystone/keystone.conf signing token_format UUID
openstack-config --set /etc/keystone/keystone.conf sql connection mysql://keystone:keystone@127.0.0.1/keystone

#Configure keystone to start at boot and start it up.

chkconfig openstack-keystone on
service openstack-keystone start # If you script this, you'll want to wait a few seconds to start using it
sleep 5

#We are using untrusted certs, so tell keystone not to complain.  If you replace with trusted certs, or are not using SSL, set this to "".

INSECURE="--insecure"

#Create the keystone and swift services in keystone:

KS_SERVICEID=$(keystone $INSECURE service-create --name=keystone --type=identity --description="Keystone Identity Service" | grep " id " | cut -d "|" -f 3)
SW_SERVICEID=$(keystone $INSECURE service-create --name=swift --type=object-store --description="Swift Service" | grep " id " | cut -d "|" -f 3)
endpoint="$http://127.0.0.1:$port"
keystone $INSECURE endpoint-create --service_id $KS_SERVICEID \
    --publicurl $endpoint'/v2.0' --adminurl $http://127.0.0.1:35357/v2.0 \
    --internalurl $http://127.0.0.1:5000/v2.0
keystone $INSECURE endpoint-create --service_id $SW_SERVICEID \
    --publicurl $endpoint'/v1/AUTH_$(tenant_id)s' \
    --adminurl $endpoint'/v1/AUTH_$(tenant_id)s' \
    --internalurl $endpoint'/v1/AUTH_$(tenant_id)s'

#Create the admin tenant:

admin_id=$(keystone $INSECURE tenant-create --name $admin_tenant --description "Internal Admin Tenant" | grep id | awk '{print $4}')

#Create the admin roles:

admin_role=$(keystone $INSECURE role-create --name admin | grep id | awk '{print $4}')
ksadmin_role=$(keystone $INSECURE role-create --name KeystoneServiceAdmin | grep id | awk '{print $4}')
kadmin_role=$(keystone $INSECURE role-create --name KeystoneAdmin | grep id | awk '{print $4}')
member_role=$(keystone $INSECURE role-create --name member | grep id | awk '{print $4}')

#Create the admin user:

user_id=$(keystone $INSECURE user-create --name admin --tenant-id $admin_id --pass $OS_PASSWORD | grep id | awk '{print $4}')
keystone $INSECURE user-role-add --user-id $user_id --tenant-id $admin_id \
    --role-id $admin_role
keystone $INSECURE user-role-add --user-id $user_id --tenant-id $admin_id \
    --role-id $kadmin_role
keystone $INSECURE user-role-add --user-id $user_id --tenant-id $admin_id \
    --role-id $ksadmin_role

#If you do not have multi-volume support (broken in 3.3.1-11), then the volume names will not correlate to the tenants, and all tenants will map to the same volume, so just use a normal name.
#(This will be fixed in 3.4, and should be fixed in 3.4 Beta.  The bug report for this is here: https://bugzilla.redhat.com/show_bug.cgi?id=924792)

#  If you have the multi-volume patch
volname=$admin_id
if [ "$multivol" -eq 0 ]; then
	volname="$admin_tenant"
fi

#Create and start the admin volume:
mount=/opt/export
if ! fgrep xvdf /etc/fstab > /dev/null; then
	mkfs -t xfs -i size=512 /dev/xvdf -f
	echo "/dev/xvdf         $mount          xfs     noatime,nodiratime      1 1" >> /etc/fstab
	mkdir $mount
fi
mount $mount

service glusterd start
gluster volume create $volname $(uname -n):/$mount/$volname
gluster volume start $volname

#Create the ring for the admin tenant.  If you have working multi-volume support, then you can specify multiple volume names in the call:

cd /etc/swift
/usr/bin/gluster-swift-gen-builders $volname
swift-init main restart

#Create a testadmin user associated with the admin tenant with password testadmin and admin role:

user_id=$(keystone $INSECURE user-create --name testadmin --tenant-id $admin_id --pass testadmin | grep id | awk '{print $4}')
keystone $INSECURE user-role-add --user-id $user_id --tenant-id $admin_id \
    --role-id $admin_role

#Test the user:

curl $INSECURE -d '{"auth":{"tenantName": "'$admin_tenant'", "passwordCredentials":{"username": "testadmin", "password": "testadmin"}}}' -H "Content-type: application/json" $http://127.0.0.1:5000/v2.0/tokens

#See here for more examples:

#  http://docs.openstack.org/developer/keystone/api_curl_examples.html

# Install the support for swift-bench
yum install -y python-swiftclient

# Make our cert trusted so swift-bench doesn't complain
#cat $cert_file >> /etc/pki/tls/certs/ca-bundle.crt

cd /tmp
cat > test.bench << _EOM_
[bench]
auth = $http://127.0.0.1:5000/v2.0/
user = admin:testadmin
key = testadmin
concurrency = 10
object_size = 1
num_objects = 1000
num_gets = 10000
delete = yes
auth_version = 2.0
_EOM_
# swift-bench /tmp/test.bench

