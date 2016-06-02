#!/bin/bash

# This script sets up Swift

export MY_PUBLIC_IP=`hostname -I | cut -f1 -d' '`
export MY_IP=`hostname -I | cut -f2 -d' '`
export MY_PRIVATE_IP=`hostname -I | cut -f2 -d' '`

sudo apt-get -y install xfsprogs rsync
sudo apt-get -y install swift swift-account swift-container swift-object swift-object-expirer swift-proxy python-swiftclient

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
sudo sed -i "s|# account_autocreate = false|account_autocreate = true|g" /etc/swift/proxy-server.conf
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

# Obtain the account server config file
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
