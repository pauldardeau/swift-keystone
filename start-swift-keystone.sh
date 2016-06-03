#!/bin/bash

# this script starts up swift-keystone

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
