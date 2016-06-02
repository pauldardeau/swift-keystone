export MY_PUBLIC_IP=`hostname -I | cut -f1 -d' '`
export MY_IP=`hostname -I | cut -f2 -d' '`
export MY_PRIVATE_IP=`hostname -I | cut -f2 -d' '`

# Install Ubuntu Cloud Keyring and Repository Manager
sudo apt-get install -y software-properties-common

# Install Ubuntu Cloud Archive repository for Liberty
sudo add-apt-repository -y cloud-archive:mitaka

# Download the latest package index to ensure you get Liberty packages
sudo apt-get update

# Install Chrony
sudo apt-get install -y chrony

# Verify time sources
chronyc sources

sudo apt-get install -y curl

# Preseed MariaDB install
cat <<EOF | sudo debconf-set-selections
mariadb-server-5.5 mysql-server/root_password password notmysql
mariadb-server-5.5 mysql-server/root_password_again password notmysql
mariadb-server-5.5 mysql-server/start_on_boot boolean true
EOF

# Install MariaDB
sudo apt-get install -y mariadb-server python-pymysql

# Configure MariaDB
sudo sed -i "s/127.0.0.1/$MY_PRIVATE_IP\nskip-name-resolve\ncharacter-set-server = utf8\ncollation-server = utf8_general_ci\ninit-connect = 'SET NAMES utf8'\ninnodb_file_per_table/g" /etc/mysql/my.cnf

# Restart MariaDB
sudo service mysql restart

# Install Memcached
sudo apt-get install -y memcached python-memcache

# Configure Memcached
sudo sed -i "s|127.0.0.1|$MY_PRIVATE_IP|g" /etc/memcached.conf

# Restart Memecached
sudo service memcached restart

# Install OpenStack Client
sudo apt-get install -y python-openstackclient

# Prevent Keystone from starting automatically
echo manual | sudo tee /etc/init/keystone.override

# Install Keystone - OpenStack Identity Service
sudo apt-get install -y keystone apache2 libapache2-mod-wsgi

# Verify version of Keystone Package (Mitaka == 2:9.0.0-0ubuntu1)
sudo dpkg -p keystone | grep "Version:"

# Create Keystone database
mysql -u root -pnotmysql -e "CREATE DATABASE keystone;"
mysql -u root -pnotmysql -e "GRANT ALL ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'notkeystone';"
mysql -u root -pnotmysql -e "GRANT ALL ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'notkeystone';"

# Configure Keystone
sudo sed -i "s|#admin_token = <None>|admin_token = ADMIN|g" /etc/keystone/keystone.conf
sudo sed -i "s|connection = sqlite:////var/lib/keystone/keystone.db|connection=mysql+pymysql://keystone:notkeystone@$MY_PRIVATE_IP/keystone|g" /etc/keystone/keystone.conf
sudo sed -i "s|#provider = uuid|provider = fernet|g" /etc/keystone/keystone.conf

# Initialize Keystone database
sudo -u keystone keystone-manage db_sync

# Initialize Fernet keys
sudo keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone

# Configure ServerName Option in apache config file
( cat | sudo tee -a /etc/apache2/apache2.conf ) <<EOF
ServerName $MY_IP
EOF

# Create and configure Keystone virtual hosts file
cat <<EOF | sudo tee /etc/apache2/sites-available/wsgi-keystone.conf
Listen 5000
Listen 35357
<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    ErrorLogFormat "%{cu}t %M"
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /usr/bin/keystone-wsgi-admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    ErrorLogFormat "%{cu}t %M"
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Enable the Keystone virtual host:
sudo a2ensite wsgi-keystone

# Restart the Apache HTTP server:
sudo service apache2 restart

# Verify Apache is running
sudo pgrep -l apache2

# Export Keystone "service" credentials to populate service catalog and create first user / tenant
export OS_TOKEN=ADMIN
export OS_URL=http://$MY_IP:35357/v3
export OS_IDENTITY_API_VERSION=3

# Populate service in service catalog
openstack service create --name keystone --description "OpenStack Identity" identity

# List services
openstack service list

# Create the public identity endpoint
openstack endpoint create --region RegionOne identity public http://$MY_PUBLIC_IP:5000/v3

# Create the internal identity endpoint
openstack endpoint create --region RegionOne identity internal http://$MY_IP:5000/v3

# Create the admin identity endpoint
openstack endpoint create --region RegionOne identity admin http://$MY_IP:35357/v3

# List endpoints
openstack endpoint list

# Create the Default domain
openstack domain create --description "Default Domain" default

# Create the MyProject project
openstack project create --domain default --description "MyProject" MyProject

# Create the Service project
openstack project create --domain default --description "Service Project" Service

# Create the 'myadmin' user
openstack user create --domain default --password mypassword myadmin

# Create the 'myuser' user
openstack user create --domain default --password mypassword myuser

# List users
openstack user list

# Create the 'admin' role
openstack role create admin

# Create the 'user' role
openstack role create _member_

# List roles
openstack role list

# Add the admin role to the admin project and user:
openstack role add --project MyProject --user myadmin admin

# Add the user role to the demo project and user
openstack role add --project MyProject --user myuser _member_

# List role assignments for 'myuser' and 'myadmin'
openstack role list --project MyProject --user myuser
openstack role list --project MyProject --user myadmin

# Unset the temporary OS_TOKEN and OS_URL environment variables
unset OS_TOKEN
unset OS_URL


# Create 'myuser' and 'myadmin' credentials
mkdir ~/credentials

cat >> ~/credentials/myadmin <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=MyProject
export OS_USERNAME=myadmin
export OS_PASSWORD=mypassword
export OS_AUTH_URL=http://$MY_IP:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

cat >> ~/credentials/myuser <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=MyProject
export OS_USERNAME=myuser
export OS_PASSWORD=mypassword
export OS_AUTH_URL=http://$MY_IP:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

# Source the myadmin credentials
source ~/credentials/myadmin

# Using python-openstackclient, list users as 'myadmin'
openstack user list

# Using python-openstackclient, get a token
openstack token issue


# Use 'myadmin' credentials
source ~/credentials/myadmin

# Create Swift service user
openstack user create --domain default --password notswift swift

# Grant 'admin' role to Swift service user
openstack role add --project Service --user swift admin

# Create the Swift service entity
openstack service create --name swift --description "OpenStack Object Storage" object-store

# Create the public object-store endpoint
openstack endpoint create --region RegionOne object-store public http://$MY_PUBLIC_IP:8080/v1/AUTH_%\(tenant_id\)s

# Create the internal object endpoint
openstack endpoint create --region RegionOne object-store internal http://$MY_IP:8080/v1/AUTH_%\(tenant_id\)s

# Create the admin object endpoint
openstack endpoint create --region RegionOne object-store admin http://$MY_IP:8080/v1/AUTH_%\(tenant_id\)s

# List the catalog of available services and endpoints
openstack catalog list

# Install Swift dependencies
sudo apt-get -y install python-keystonemiddleware memcached xfsprogs rsync

# Install Swift - OpenStack Object Storage
sudo apt-get -y install swift swift-account swift-container swift-object swift-object-expirer swift-proxy python-swiftclient

# Ensure swift owns everything in it's cache directory
sudo chown -R swift: /var/cache/swift

# Set up the filesystems
sudo mkfs.xfs -f -i size=1024 /dev/loop2
sudo mkfs.xfs -f -i size=1024 /dev/loop3
sudo mkfs.xfs -f -i size=1024 /dev/loop4
sudo mkfs.xfs -f -i size=1024 /dev/loop5
sudo mkfs.xfs -f -i size=1024 /dev/loop6
sudo mkfs.xfs -f -i size=1024 /dev/loop7

# Create the mount points
sudo mkdir -p /srv/node/loop{2,3,4,5,6,7}

# Setup drives to be mounted in /etc/fstab (notice noauto)
( cat | sudo tee -a /etc/fstab ) <<EOF
/dev/loop2 /srv/node/loop2 xfs noauto,noatime,nodiratime,nobarrier,logbufs=8 0 0
/dev/loop3 /srv/node/loop3 xfs noauto,noatime,nodiratime,nobarrier,logbufs=8 0 0
/dev/loop4 /srv/node/loop4 xfs noauto,noatime,nodiratime,nobarrier,logbufs=8 0 0
/dev/loop5 /srv/node/loop5 xfs noauto,noatime,nodiratime,nobarrier,logbufs=8 0 0
/dev/loop6 /srv/node/loop6 xfs noauto,noatime,nodiratime,nobarrier,logbufs=8 0 0
/dev/loop7 /srv/node/loop7 xfs noauto,noatime,nodiratime,nobarrier,logbufs=8 0 0
EOF

# Mount the drives now
sudo mount /srv/node/loop2
sudo mount /srv/node/loop3
sudo mount /srv/node/loop4
sudo mount /srv/node/loop5
sudo mount /srv/node/loop6
sudo mount /srv/node/loop7

# Mount the drives at boot
( cat | sudo tee /etc/rc.local ) <<EOF
#!/bin/sh -e

mount /srv/node/loop2
mount /srv/node/loop3
mount /srv/node/loop4
mount /srv/node/loop5
mount /srv/node/loop6
mount /srv/node/loop7

exit 0
EOF

# Ensure swift user owns everything
sudo chown -R swift: /srv/node

# Make /etc/swift directory
sudo mkdir -p /etc/swift

# Obtain the proxy service configuration file from the Swift source repository
sudo curl -o /etc/swift/proxy-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/proxy-server.conf-sample?h=stable/mitaka

# Modify Proxy-server.conf
sudo sed -i "s|pipeline = catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk tempurl ratelimit tempauth container-quotas account-quotas slo dlo versioned_writes proxy-logging proxy-server|pipeline = catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk ratelimit authtoken keystoneauth staticweb container-quotas account-quotas slo dlo versioned_writes proxy-logging proxy-server|g" /etc/swift/proxy-server.conf
sudo sed -i "s|# account_autocreate = false|account_autocreate = true|g" /etc/swift/proxy-server.conf
sudo sed -i "s|# \[filter:authtoken\]|\[filter:authtoken\]\npaste.filter_factory = keystonemiddleware.auth_token:filter_factory\nauth_uri = http://$MY_PRIVATE_IP:5000\nauth_url = http://$MY_PRIVATE_IP:35357\nmemcached_servers = $MY_IP:11211\nauth_plugin = password\nproject_domain_name = default\nuser_domain_name = default\nproject_name = Service\nusername = swift\npassword = notswift\ndelay_auth_decision = true|g" /etc/swift/proxy-server.conf
sudo sed -i "s|# \[filter:keystoneauth\]|\[filter:keystoneauth\]|g" /etc/swift/proxy-server.conf
sudo sed -i "s|# use = egg:swift#keystoneauth|use = egg:swift#keystoneauth|g" /etc/swift/proxy-server.conf
sudo sed -i "s|# memcache_servers = 127.0.0.1:11211|memcache_servers = $MY_IP:11211|g" /etc/swift/proxy-server.conf
sudo sed -i "s|# allow_versioned_writes = false|allow_versioned_writes = true|g" /etc/swift/proxy-server.conf

# Set default domain id to allow use use of names in acls
DEFAULT_DOMAIN_ID=`openstack domain list | awk '/ default / { print $2 }'`
sudo sed -i "s|# default_domain_id = default|default_domain_id = $DEFAULT_DOMAIN_ID|g" /etc/swift/proxy-server.conf

# Configure rsync
sudo sed -i 's/RSYNC_ENABLE=false/RSYNC_ENABLE=true/g' /etc/default/rsync

( cat | sudo tee /etc/rsyncd.conf ) <<EOF
uid = swift
gid = swift
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
address = 0.0.0.0

[account]
max connections = 2
path = /srv/node/
read only = false
lock file = /var/lock/account.lock

[container]
max connections = 2
path = /srv/node/
read only = false
lock file = /var/lock/container.lock

[object]
max connections = 2
path = /srv/node/
read only = false
lock file = /var/lock/object.lock
EOF

# Restart rsync
sudo service rsync restart

# Obtain the accounting config file
sudo curl -o /etc/swift/account-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/account-server.conf-sample?=stable/mitaka

# Modify account-server.conf
sudo sed -i "s|bind_port = 6202|bind_port = 6002|g" /etc/swift/account-server.conf

# Obtain the container and object server config files
sudo curl -o /etc/swift/container-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/container-server.conf-sample?h=stable/mitaka
sudo curl -o /etc/swift/object-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/object-server.conf-sample?h=stable/mitaka

# Obtain the object-expirer configuration file from the Swift source repository 
sudo curl -o /etc/swift/object-expirer.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/object-expirer.conf-sample?=stable/mitaka

# Modify object-expirer.conf
sudo sed -i "s|use = egg:swift#memcache|use = egg:swift#memcache\nmemcache_servers = $MY_IP:11211|g" /etc/swift/object-expirer.conf

# Obtain the container-reconciler configuration file from the Swift source repository 
sudo curl -o /etc/swift/container-reconciler.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/container-reconciler.conf-sample?=stable/mitaka

# Modify container-reconciler.conf
sudo sed -i "s|use = egg:swift#memcache|use = egg:swift#memcache\nmemcache_servers = $MY_IP:11211|g" /etc/swift/container-reconciler.conf

# Obtain Swift configuration file from the Swift source repository 
sudo curl -o /etc/swift/swift.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/swift.conf-sample?h=stable/mitaka

sudo chown -R root:swift /etc/swift

# Create Swift admin user
openstack user create --domain default --password mypassword swiftadmin

# Create Swift operator role
openstack role create swiftoperator

# Grant 'swiftoperator' role to 'swiftadmin' user
openstack role add --project MyProject --user swiftadmin swiftoperator

# Create the credentials file for the swiftadmin account
cat >> ~/credentials/swiftadmin <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=MyProject
export OS_USERNAME=swiftadmin
export OS_PASSWORD=mypassword
export OS_AUTH_URL=http://$MY_IP:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF


# Create the rings
cd /etc/swift

# Create the object ring
sudo swift-ring-builder object.builder create 9 3 1
sudo swift-ring-builder object.builder add r1z1-$MY_PRIVATE_IP:6000/loop2 1000
sudo swift-ring-builder object.builder add r1z2-$MY_PRIVATE_IP:6000/loop3 1000
sudo swift-ring-builder object.builder add r1z3-$MY_PRIVATE_IP:6000/loop4 1000
sudo swift-ring-builder object.builder add r1z4-$MY_PRIVATE_IP:6000/loop5 1000

# Create the container ring
sudo swift-ring-builder container.builder create 9 3 1
sudo swift-ring-builder container.builder add r1z1-$MY_PRIVATE_IP:6001/loop2 1000
sudo swift-ring-builder container.builder add r1z2-$MY_PRIVATE_IP:6001/loop3 1000
sudo swift-ring-builder container.builder add r1z3-$MY_PRIVATE_IP:6001/loop4 1000
sudo swift-ring-builder container.builder add r1z4-$MY_PRIVATE_IP:6001/loop5 1000

# Create the account ring
sudo swift-ring-builder account.builder create 9 3 1
sudo swift-ring-builder account.builder add r1z1-$MY_PRIVATE_IP:6002/loop2 1000
sudo swift-ring-builder account.builder add r1z2-$MY_PRIVATE_IP:6002/loop3 1000
sudo swift-ring-builder account.builder add r1z3-$MY_PRIVATE_IP:6002/loop4 1000
sudo swift-ring-builder account.builder add r1z4-$MY_PRIVATE_IP:6002/loop5 1000

# Verify the contents of each ring
sudo swift-ring-builder object.builder
sudo swift-ring-builder container.builder
sudo swift-ring-builder account.builder

# Rebalance each ring using a seed value
sudo swift-ring-builder object.builder rebalance 1337
sudo swift-ring-builder container.builder rebalance 1337
sudo swift-ring-builder account.builder rebalance 1337

# Notice the distribution of partitions amongst the storage locations
sudo swift-ring-builder object.builder
sudo swift-ring-builder container.builder
sudo swift-ring-builder account.builder

# Ensure all files are owned by swift
sudo chown -R swift: /etc/swift

# Start the swift services
sudo swift-init all restart

# Inspect the running swift services
sudo swift-init all status

# Navigate back to home directory
cd

# Use the project 'swiftadmin' credentials
source ~/credentials/swiftadmin

# Show stats (containers, objects, etc)
swift stat