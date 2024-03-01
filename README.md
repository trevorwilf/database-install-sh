# freebsd-database-install
Script to automate installing different databases

## Status
This script should work out of the box with any FreeBSD version

## Usage

### Prerequisites
* The only prerequisite is to edit the included `db-config` file with your preferred database, database name and database user

### Installation
Download the repository to a convenient directory on your FreeBSD system (or jail) by changing to that directory and running `git clone https://github.com/tschettervictor/freebsd-database-install`.  Then change into the new `freebsd-database-install` directory and edit the `db-config` file with your preferred values, and set one of the database variables to "1". Only ONE of the databases should be set to "1", otherwise the script will return an error.
```
MARIADB=0
MYSQL=0
POSTGRESQL=0
DB_NAME="databasename"
DB_USER="databaseuser"
```

### Execution
Once you've downloaded the script and prepared the configuration file, run the script ( eg: `./db-install.sh` ). The script will run for maybe a minute. When it finishes, your database will be configured, and you will be shown the root password as well as the user password for the database

### Notes
- This script is a simple straightforward script to get a database up and running quickly and efficiently
