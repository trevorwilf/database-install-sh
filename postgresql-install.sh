#!/bin/sh
# Install and configure PostgreSQL database with predefined variables
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
CONFIG_NAME="db-config"
DATABASE="PostgreSQL"
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

# Check that necessary variables were set by db-config
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
pkg install -y postgresql15-server postgresql15-client
sysrc postgresql_enable=yes
cp -f "${INCLUDES_PATH}"/pgpass /root/.pgpass
chmod 600 /root/.pgpass
mkdir -p /var/db/postgres
chown postgres /var/db/postgres
service postgresql initdb
service postgresql start
sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.pgpass

if ! psql -U postgres -c "CREATE DATABASE ${DB_NAME};" then
	echo "Failed to create PostgreSQL database, aborting"
	exit 1
fi
psql -U postgres -c "CREATE USER ${DB_USER} WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';"
psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
psql -U postgres -c "ALTER DATABASE ${DB_NAME} OWNER to ${DB_USER};"
psql -U postgres -c "SELECT pg_reload_conf();"

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
