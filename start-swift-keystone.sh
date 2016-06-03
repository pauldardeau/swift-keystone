#!/bin/bash

# this script starts up swift-keystone

export CREDS_DIR="${HOME}/credentials"

# Start the swift services
sudo swift-init all restart

# Inspect the running swift services
sudo swift-init all status

# Use the project 'swiftadmin' credentials
source ${CREDS_DIR}/swiftadmin

# Show stats (containers, objects, etc)
swift stat
