# freebsd-database-scripts
List of scripts to automate installing different databases

## Status
This script should work out of the box with any FreeBSD version

## Usage

### Prerequisites
* The only prerequisite is to edit the included `db-config` file with your preferred database name and database user

### Installation
Download the repository to a convenient directory on your FreeBSD system by changing to that directory and running `git clone https://github.com/tschettervictor/freebsd-database-scripts`.  Then change into the new `freebsd-database-scripts` directory and edit the `db-config` file with your preferred values
```
DB_NAME="databasename"
DB_USER="databaseuser"
```

### Execution
Once you've downloaded the script and prepared the configuration file, run the preferred database script ( eg: `mysql-install.sh` ). The script will run for maybe a minute. When it finishes, your database will be configured, and you will be shown the root password as well as the user password for the database

### Notes
- These scripts are simple straightforward scripts to get a database up and running quickly and efficiently
