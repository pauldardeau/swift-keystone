#!/bin/bash

# this script sets up keystone, swift, and then keystone-swift integration

export MY_PUBLIC_IP=`hostname -I | cut -f1 -d' '`
export MY_IP=`hostname -I | cut -f2 -d' '`
export MY_PRIVATE_IP=`hostname -I | cut -f2 -d' '`

./setup-prereqs.sh
./setup-keystone.sh
./setup-swift.sh
./setup-swift-keystone.sh
./start-swift-keystone.sh
