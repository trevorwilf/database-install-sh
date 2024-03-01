#!/bin/sh
# Install and configure MariaDB database with predefined variables
# git clone https://github.com/tschettervictor/freebsd-database-scripts

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
CONFIG_NAME="mariadb-config"
DATABASE="MariaDB"
DB_NAME=""
DB_USER=""
DB_ROOT_PASSWORD=$(openssl rand -base64 15)
DB_PASSWORD=$(openssl rand -base64 15)

# Check for mariadb-config and set configuration
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
if ! [ -e "${SCRIPTPATH}"/"${CONFIG_NAME}" ]; then
  echo "${SCRIPTPATH}/${CONFIG_NAME} must exist."
  exit 1
fi
. "${SCRIPTPATH}"/"${CONFIG_NAME}"
INCLUDES_PATH="${SCRIPTPATH}"/includes

#####
#
# Input/Config Sanity checks
#
#####

# Check that necessary variables were set by mariadb-config
if [ -z "${DB_NAME}" ]; then
  echo 'Configuration error: DB_NAME must be set'
  exit 1
fi
if [ -z "${DB_USER}" ]; then
  echo 'Configuration error: DB_USER must be set'
  exit 1
fi

#####
#
# Database Installation
#
#####

if ! mysql -u root -e "CREATE DATABASE ${DB_NAME};"; then
	echo "Failed to create MariaDB database, aborting"
	exit 1
fi
mysql -u root -e "GRANT ALL ON ${DB_NAME}.* TO '${DB_USER}'@localhost IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -u root -e "DROP DATABASE IF EXISTS test;"
mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -u root -e "FLUSH PRIVILEGES;"
mysqladmin --user=root password "${DB_ROOT_PASSWORD}" reload
cp -f "${INCLUDES_PATH}"/my.cnf /root/.my.cnf
sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.my.cnf

# Save Passwords
echo "${DATABASE} root user is root and password is ${DB_ROOT_PASSWORD}" > /root/${DB_NAME}_db_password.txt
echo "${DB_NAME} database user is ${DB_USER} and password is ${DB_PASSWORD}" >> /root/${DB_NAME}_db_password.txt

echo "---------------"
echo "Installation complete."
echo "---------------"
echo "Database Information"
echo "$DATABASE Username: root"
echo "$DATABASE Password: $DB_ROOT_PASSWORD"
echo "$DB_NAME User: $DB_USER"
echo "$DB_NAME Password: "$DB_PASSWORD""

echo "---------------"
echo "All passwords are saved in /root/${DB_NAME}_db_password.txt"
echo "---------------"
