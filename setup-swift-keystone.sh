#!/bin/bash

# this script sets up swift to integrate with keystone

# Modify Proxy-server.conf
sudo sed -i "s|pipeline = catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk tempurl ratelimit tempauth container-quotas account-quotas slo dlo versioned_writes proxy-logging proxy-server|pipeline = catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk ratelimit authtoken keystoneauth staticweb container-quotas account-quotas slo dlo versioned_writes proxy-logging proxy-server|g" /etc/swift/proxy-server.conf
sudo sed -i "s|# \[filter:authtoken\]|\[filter:authtoken\]\npaste.filter_factory = keystonemiddleware.auth_token:filter_factory\nauth_uri = http://$MY_PRIVATE_IP:5000\nauth_url = http://$MY_PRIVATE_IP:35357\nmemcached_servers = $MY_IP:11211\nauth_plugin = password\nproject_domain_name = default\nuser_domain_name = default\nproject_name = Service\nusername = swift\npassword = notswift\ndelay_auth_decision = true|g" /etc/swift/proxy-server.conf
sudo sed -i "s|# \[filter:keystoneauth\]|\[filter:keystoneauth\]|g" /etc/swift/proxy-server.conf
sudo sed -i "s|# use = egg:swift#keystoneauth|use = egg:swift#keystoneauth|g" /etc/swift/proxy-server.conf
