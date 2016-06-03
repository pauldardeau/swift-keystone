#!/bin/bash

# This script sets up Keystone

export OS_RELEASE="mitaka"
export MY_PUBLIC_IP="127.0.0.1"
export MY_IP="127.0.0.1"
export MY_PRIVATE_IP="127.0.0.1"

sudo apt-get install -y python-openstackclient

# Preseed MariaDB install
cat <<EOF | sudo debconf-set-selections
mariadb-server-5.5 mysql-server/root_password password notmysql
mariadb-server-5.5 mysql-server/root_password_again password notmysql
mariadb-server-5.5 mysql-server/start_on_boot boolean true
EOF

sudo apt-get install -y mariadb-server
sudo pip install PyMySQL
sudo apt-get install -y apache2 libapache2-mod-wsgi
sudo apt-get install -y keystone

sudo sed -i "s/127.0.0.1/${MY_PRIVATE_IP}\nskip-name-resolve\ncharacter-set-server = utf8\ncollation-server = utf8_general_ci\ninit-connect = 'SET NAMES utf8'\ninnodb_file_per_table/g" /etc/mysql/my.cnf
sudo sed -i "s|127.0.0.1|${MY_PRIVATE_IP}|g" /etc/memcached.conf

sudo service mysql restart
sudo service memcached restart

# Configure ServerName Option in apache config file
( cat | sudo tee -a /etc/apache2/apache2.conf ) <<EOF
ServerName $MY_IP
EOF

# Prevent Keystone from starting automatically
echo manual | sudo tee /etc/init/keystone.override

# Create Keystone database
mysql -u root -pnotmysql -e "DROP DATABASE keystone;"
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

# Verify version of Keystone Package
sudo dpkg -p keystone | grep "Version:"


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
export OS_URL=http://${MY_IP}:35357/v3
export OS_IDENTITY_API_VERSION=3

# Populate service in service catalog
openstack service create --name keystone --description "OpenStack Identity" identity
openstack service list

openstack endpoint create --region RegionOne identity public http://${MY_PUBLIC_IP}:5000/v3
openstack endpoint create --region RegionOne identity internal http://${MY_IP}:5000/v3
openstack endpoint create --region RegionOne identity admin http://${MY_IP}:35357/v3
openstack endpoint list

openstack domain create --description "Default Domain" default

openstack project create --domain default --description "MyProject" MyProject
openstack project create --domain default --description "Service Project" Service

openstack user create --domain default --password mypassword myadmin
openstack user create --domain default --password mypassword myuser
openstack user list

openstack role create admin
openstack role create _member_
openstack role list

openstack role add --project MyProject --user myadmin admin
openstack role add --project MyProject --user myuser _member_

openstack role list --project MyProject --user myuser
openstack role list --project MyProject --user myadmin

# Unset the temporary OS_TOKEN and OS_URL environment variables
unset OS_TOKEN
unset OS_URL

CREDS_DIR="${HOME}/credentials"

if [ -d ${CREDS_DIR} ]; then
  rm -f "${CREDS_DIR}/myadmin"
  rm -f "${CREDS_DIR}/myuser"
else
  mkdir ${CREDS_DIR}
fi

cat > ${CREDS_DIR}/myadmin <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=MyProject
export OS_USERNAME=myadmin
export OS_PASSWORD=mypassword
export OS_AUTH_URL=http://${MY_IP}:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

cat > ${CREDS_DIR}/myuser <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=MyProject
export OS_USERNAME=myuser
export OS_PASSWORD=mypassword
export OS_AUTH_URL=http://${MY_IP}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
