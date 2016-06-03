#!/bin/bash

# This script sets up Swift

export OS_RELEASE="mitaka"
export MY_PUBLIC_IP="127.0.0.1"
export MY_IP="127.0.0.1"
export MY_PRIVATE_IP="127.0.0.1"
export CREDS_DIR="${HOME}/credentials"

sudo apt-get -y install rsync
sudo apt-get -y install swift swift-account swift-container swift-object swift-object-expirer swift-proxy python-swiftclient

sudo mkdir -p /etc/swift
sudo chown -R swift:swift /var/cache/swift
sudo chown -R swift:swift /etc/swift

# Obtain the proxy service configuration file from the Swift source repository
sudo curl -o /etc/swift/proxy-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/proxy-server.conf-sample?h=stable/${OS_RELEASE}

# Modify Proxy-server.conf
sudo sed -i "s|# account_autocreate = false|account_autocreate = true|g" /etc/swift/proxy-server.conf
sudo sed -i "s|# memcache_servers = 127.0.0.1:11211|memcache_servers = ${MY_IP}:11211|g" /etc/swift/proxy-server.conf
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

# Obtain the account server config file
sudo curl -o /etc/swift/account-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/account-server.conf-sample?=stable/${OS_RELEASE}

# Modify account-server.conf
sudo sed -i "s|bind_port = 6202|bind_port = 6002|g" /etc/swift/account-server.conf

# Obtain the container and object server config files
sudo curl -o /etc/swift/container-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/container-server.conf-sample?h=stable/${OS_RELEASE}
sudo curl -o /etc/swift/object-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/object-server.conf-sample?h=stable/${OS_RELEASE}

# Obtain the object-expirer configuration file from the Swift source repository 
sudo curl -o /etc/swift/object-expirer.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/object-expirer.conf-sample?=stable/${OS_RELEASE}

# Modify object-expirer.conf
sudo sed -i "s|use = egg:swift#memcache|use = egg:swift#memcache\nmemcache_servers = ${MY_IP}:11211|g" /etc/swift/object-expirer.conf

# Obtain the container-reconciler configuration file from the Swift source repository 
sudo curl -o /etc/swift/container-reconciler.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/container-reconciler.conf-sample?=stable/${OS_RELEASE}

# Modify container-reconciler.conf
sudo sed -i "s|use = egg:swift#memcache|use = egg:swift#memcache\nmemcache_servers = ${MY_IP}:11211|g" /etc/swift/container-reconciler.conf

# Obtain Swift configuration file from the Swift source repository 
sudo curl -o /etc/swift/swift.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/swift.conf-sample?h=stable/${OS_RELEASE}

# Create the credentials file for the swiftadmin account
cat > ${CREDS_DIR}/swiftadmin <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=MyProject
export OS_USERNAME=swiftadmin
export OS_PASSWORD=mypassword
export OS_AUTH_URL=http://${MY_IP}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

