#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

apt-get -y install xfsprogs

SWIFT_USER="swift"
SWIFT_GROUP="swift"
SWIFT_DISK_SIZE_GB="1"
SWIFT_DISK_BASE_DIR="/srv"
SWIFT_MOUNT_BASE_DIR="/mnt"

mkdir -p "${SWIFT_DISK_BASE_DIR}"
mkdir -p "${SWIFT_MOUNT_BASE_DIR}"

SWIFT_DISK="${SWIFT_DISK_BASE_DIR}/swift-disk"
for x in {1..8}; do
   SWIFT_DISK="${SWIFT_DISK_BASE_DIR}/swift-disk${x}"
   truncate -s "${SWIFT_DISK_SIZE_GB}GB" "${SWIFT_DISK}"
   mkfs.xfs -f "${SWIFT_DISK}"
done

# good idea to have backup of fstab before we modify it
cp /etc/fstab /etc/fstab.insert.bak

cat >> /etc/fstab << EOF
/srv/swift-disk1 /srv/1/node/sdb1 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0
/srv/swift-disk2 /srv/2/node/sdb2 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0
/srv/swift-disk3 /srv/3/node/sdb3 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0
/srv/swift-disk4 /srv/4/node/sdb4 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0
/srv/swift-disk5 /srv/1/node/sdb5 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0
/srv/swift-disk6 /srv/2/node/sdb6 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0
/srv/swift-disk7 /srv/3/node/sdb7 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0
/srv/swift-disk8 /srv/4/node/sdb8 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0
EOF

for x in {1..4}; do
   SWIFT_DISK_DIR="${SWIFT_DISK_BASE_DIR}/${x}"
   SWIFT_MOUNT_DIR="${SWIFT_MOUNT_BASE_DIR}/${x}"
   mkdir ${SWIFT_MOUNT_DIR}
   chown ${SWIFT_USER}:${SWIFT_GROUP} ${SWIFT_MOUNT_DIR}
   ln -s ${SWIFT_MOUNT_DIR} ${SWIFT_DISK_DIR}
done

mkdir -p ${SWIFT_DISK_BASE_DIR}/1/node/sdb1
mkdir -p ${SWIFT_DISK_BASE_DIR}/2/node/sdb2
mkdir -p ${SWIFT_DISK_BASE_DIR}/3/node/sdb3
mkdir -p ${SWIFT_DISK_BASE_DIR}/4/node/sdb4

mkdir -p ${SWIFT_DISK_BASE_DIR}/1/node/sdb5
mkdir -p ${SWIFT_DISK_BASE_DIR}/2/node/sdb6
mkdir -p ${SWIFT_DISK_BASE_DIR}/3/node/sdb7
mkdir -p ${SWIFT_DISK_BASE_DIR}/4/node/sdb8

chown -R ${SWIFT_USER}:${SWIFT_GROUP} ${SWIFT_DISK_BASE_DIR}

mount -a

for x in {1..4}; do
   SWIFT_MOUNT_DIR="${SWIFT_MOUNT_BASE_DIR}/${x}"
   chown -R ${SWIFT_USER}:${SWIFT_GROUP} ${SWIFT_MOUNT_DIR}/node/
done

chown -R ${SWIFT_USER}:${SWIFT_GROUP} ${SWIFT_DISK_BASE_DIR}

