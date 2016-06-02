#!/bin/bash

# this script sets up prerequisites for swift-keystone

# Install Ubuntu Cloud Keyring and Repository Manager
sudo apt-get install -y software-properties-common

# Install Ubuntu Cloud Archive repository for Mitaka
sudo add-apt-repository -y cloud-archive:mitaka

# Download the latest package index to ensure you get Mitaka packages
sudo apt-get update

# Install Chrony
sudo apt-get install -y chrony

# Verify time sources
chronyc sources

sudo apt-get install -y curl
sudo apt-get install -y memcached python-memcache