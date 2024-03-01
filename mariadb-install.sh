#!/bin/sh
# Build an iocage jail under TrueNAS 13.0 using the current release of Caddy with Guacamole
# git clone https://github.com/tschettervictor/truenas-iocage-guacamole

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

#####
#
# General configuration
#
#####

# Initialize defaults
JAIL_IP=""
JAIL_INTERFACES=""
DEFAULT_GW_IP=""
INTERFACE="vnet0"
VNET="on"
POOL_PATH=""
DB_PATH=""
JAIL_NAME="guacamole"
HOST_NAME=""
SELFSIGNED_CERT=0
STANDALONE_CERT=0
DNS_CERT=0
NO_CERT=0
CERT_EMAIL=""
CONFIG_NAME="guacamole-config"
DATABASE="mariadb"
DB_NAME="guacamole"
DB_USER="guacamole"
DB_ROOT_PASSWORD=$(openssl rand -base64 15)
DB_PASSWORD=$(openssl rand -base64 15)

# Check for guacamole-config and set configuration
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
if ! [ -e "${SCRIPTPATH}"/"${CONFIG_NAME}" ]; then
  echo "${SCRIPTPATH}/${CONFIG_NAME} must exist."
  exit 1
fi
. "${SCRIPTPATH}"/"${CONFIG_NAME}"
INCLUDES_PATH="${SCRIPTPATH}"/includes

JAILS_MOUNT=$(zfs get -H -o value mountpoint $(iocage get -p)/iocage)
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"
# If release is 13.1-RELEASE, change to 13.2-RELEASE
if [ "${RELEASE}" = "13.1-RELEASE" ]; then
  RELEASE="13.2-RELEASE"
fi 

#####
#
# Input/Config Sanity checks
#
#####

# Check that necessary variables were set by guacamole-config
if [ -z "${JAIL_IP}" ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z "${JAIL_INTERFACES}" ]; then
  echo 'JAIL_INTERFACES not set, defaulting to: vnet0:bridge0'
JAIL_INTERFACES="vnet0:bridge0"
fi
if [ -z "${DEFAULT_GW_IP}" ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z "${POOL_PATH}" ]; then
  echo 'Configuration error: POOL_PATH must be set'
  exit 1
fi
if [ -z "${HOST_NAME}" ]; then
  echo 'Configuration error: HOST_NAME must be set'
  exit 1
fi

# Check cert config
if [ $STANDALONE_CERT -eq 0 ] && [ $DNS_CERT -eq 0 ] && [ $NO_CERT -eq 0 ] && [ $SELFSIGNED_CERT -eq 0 ]; then
  echo 'Configuration error: Either STANDALONE_CERT, DNS_CERT, NO_CERT,'
  echo 'or SELFSIGNED_CERT must be set to 1.'
  exit 1
fi
if [ $STANDALONE_CERT -eq 1 ] && [ $DNS_CERT -eq 1 ] ; then
  echo 'Configuration error: Only one of STANDALONE_CERT and DNS_CERT'
  echo 'may be set to 1.'
  exit 1
fi
if [ $DNS_CERT -eq 1 ] && [ -z "${DNS_PLUGIN}" ] ; then
  echo "DNS_PLUGIN must be set to a supported DNS provider."
  echo "See https://caddyserver.com/download for available plugins."
  echo "Use only the last part of the name.  E.g., for"
  echo "\"github.com/caddy-dns/cloudflare\", enter \"coudflare\"."
  exit 1
fi
if [ $DNS_CERT -eq 1 ] && [ "${CERT_EMAIL}" = "" ] ; then
  echo "CERT_EMAIL must be set when using Let's Encrypt certs."
  exit 1
fi
if [ $STANDALONE_CERT -eq 1 ] && [ "${CERT_EMAIL}" = "" ] ; then
  echo "CERT_EMAIL must be set when using Let's Encrypt certs."
  exit 1
fi

# If DB_PATH and CONFIG_PATH weren't set, set them
if [ -z "${DB_PATH}" ]; then
  DB_PATH="${POOL_PATH}"/guacamole/db
fi

# Sanity check DB_PATH must be different from POOL_PATH
if [ "${DB_PATH}" = "${POOL_PATH}" ]
then
  echo "DB_PATH must be different from POOL_PATH!"
  exit 1
fi

# Extract IP and netmask, sanity check netmask
IP=$(echo ${JAIL_IP} | cut -f1 -d/)
NETMASK=$(echo ${JAIL_IP} | cut -f2 -d/)
if [ "${NETMASK}" = "${IP}" ]
then
  NETMASK="24"
fi
if [ "${NETMASK}" -lt 8 ] || [ "${NETMASK}" -gt 30 ]
then
  NETMASK="24"
fi

# Check for reinstall
if [ "$(ls -A "${DB_PATH}")" ]; then
	echo "Existing Guacamole database detected. Checking compatability for reinstall."
	if [ "$(ls -A "${DB_PATH}/${DATABASE}")" ]; then
		echo "Database is compatible, continuing..."
		REINSTALL="true"
	else
		echo "ERROR: You can not reinstall without the previous database"
		echo "Please try again after removing the database, or using the same database used previously"
		exit 1
	fi
fi

#####
#
# Jail Creation
#
#####

# List packages to be auto-installed after jail creation
cat <<__EOF__ >/tmp/pkg.json
{
  "pkgs": [
  "nano",
  "go",
  "guacamole-server",
  "guacamole-client",
  "mariadb106-server",
  "mariadb106-client",
  "mysql-connector-j"
  ]
}
__EOF__

# Create the jail and install previously listed packages
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" interfaces="${JAIL_INTERFACES}" ip4_addr="${INTERFACE}|${IP}/${NETMASK}" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

#####
#
# Directory Creation and Mounting
#
#####

mkdir -p "${DB_PATH}"/"${DATABASE}"
chown -R 88:88 "${DB_PATH}"/
iocage exec "${JAIL_NAME}" mkdir -p /var/db/mysql
iocage exec "${JAIL_NAME}" mkdir -p /mnt/includes
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/rc.d
iocage fstab -a "${JAIL_NAME}" "${DB_PATH}"/"${DATABASE}" /var/db/mysql nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/guacamole-client/lib
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/guacamole-client/extensions

#####
#
# Guacamole Install
#
#####

# Enable services
iocage exec "${JAIL_NAME}" sysrc guacd_enable="YES"
iocage exec "${JAIL_NAME}" sysrc tomcat9_enable="YES"
iocage exec "${JAIL_NAME}" sysrc mysql_enable="YES"

# Extract java connector to guacamole
iocage exec "${JAIL_NAME}" "cp -f /usr/local/share/java/classes/mysql-connector-j.jar /usr/local/etc/guacamole-client/lib"
iocage exec "${JAIL_NAME}" "tar xvfz /usr/local/share/guacamole-client/guacamole-auth-jdbc.tar.gz -C /tmp/"
iocage exec "${JAIL_NAME}" "cp -f /tmp/guacamole-auth-jdbc-*/mysql/*.jar /usr/local/etc/guacamole-client/extensions"

# Copy guacamole server files
iocage exec "${JAIL_NAME}" "cp -f /usr/local/etc/guacamole-server/guacd.conf.sample /usr/local/etc/guacamole-server/guacd.conf"
iocage exec "${JAIL_NAME}" "cp -f /usr/local/etc/guacamole-client/logback.xml.sample /usr/local/etc/guacamole-client/logback.xml"
iocage exec "${JAIL_NAME}" "cp -f /usr/local/etc/guacamole-client/guacamole.properties.sample /usr/local/etc/guacamole-client/guacamole.properties"

# Change default bind host ip
iocage exec "${JAIL_NAME}" sed -i -e 's/'localhost'/'0.0.0.0'/g' /usr/local/etc/guacamole-server/guacd.conf

# Add database connection
iocage exec "${JAIL_NAME}" 'echo "mysql-hostname: localhost" >> /usr/local/etc/guacamole-client/guacamole.properties'
iocage exec "${JAIL_NAME}" 'echo "mysql-port:     3306" >> /usr/local/etc/guacamole-client/guacamole.properties'
iocage exec "${JAIL_NAME}" 'echo "mysql-database: '${DB_NAME}'" >> /usr/local/etc/guacamole-client/guacamole.properties'
iocage exec "${JAIL_NAME}" 'echo "mysql-username: '${DB_USER}'" >> /usr/local/etc/guacamole-client/guacamole.properties'
iocage exec "${JAIL_NAME}" 'echo "mysql-password: '${DB_PASSWORD}'" >> /usr/local/etc/guacamole-client/guacamole.properties'
iocage exec "${JAIL_NAME}" service mysql-server start

if [ "${REINSTALL}" == "true" ]; then
	echo "You did a reinstall, but database passwords will still be changed."
 	echo "New passwords will still be saved in the TrueNAS root directory."
 	iocage exec "${JAIL_NAME}" mysql -u root -e "SET PASSWORD FOR '${DB_USER}'@localhost = PASSWORD('${DB_PASSWORD}');"
 	iocage exec "${JAIL_NAME}" cp -f /mnt/includes/my.cnf /root/.my.cnf
  	iocage exec "${JAIL_NAME}" sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.my.cnf
else
	if ! iocage exec "${JAIL_NAME}" mysql -u root -e "CREATE DATABASE ${DB_NAME};"; then
		echo "Failed to create MariaDB database, aborting"
		exit 1
	fi
		iocage exec "${JAIL_NAME}" mysql -u root -e "GRANT ALL ON ${DB_NAME}.* TO '${DB_USER}'@localhost IDENTIFIED BY '${DB_PASSWORD}';"
		iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
		iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
		iocage exec "${JAIL_NAME}" mysql -u root -e "DROP DATABASE IF EXISTS test;"
		iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
		iocage exec "${JAIL_NAME}" mysql -u root -e "FLUSH PRIVILEGES;"
		iocage exec "${JAIL_NAME}" mysqladmin --user=root password "${DB_ROOT_PASSWORD}" reload
		iocage exec "${JAIL_NAME}" cp -f /mnt/includes/my.cnf /root/.my.cnf
		iocage exec "${JAIL_NAME}" sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.my.cnf
		iocage exec "${JAIL_NAME}" "cat /tmp/guacamole-auth-jdbc-*/mysql/schema/*.sql | mysql -u root -p"${DB_ROOT_PASSWORD}" ${DB_NAME}"
fi


echo "---------------"
echo "Database Information"
echo "MySQL Username: root"
echo "MySQL Password: $DB_ROOT_PASSWORD"
echo "DB User: $DB_USER"
echo "DB Password: "$DB_PASSWORD""

echo "---------------"
echo "All passwords are saved in /root/${JAIL_NAME}_db_password.txt"
echo "---------------"
