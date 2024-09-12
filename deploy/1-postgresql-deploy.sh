#!/bin/bash

##
# Example of use:
# /bin/bash ./1-postgresql-deploy.sh 'pg_api_pwd=xxx pg_cabinet_pwd=xxx api_srv_ip=x.x.x.x'
##

## OS detection
os_base=$(cat /etc/os-release | grep -E '^ID=' | awk '{print $2}' FS="=" | tr -d '"')

## Check for supported OS
if ! [[ "$os_base" =~ debian|ubuntu|rhel|centos|rocky ]]
then
  echo -e "\033[0;101mUnsupported operating system. Please, contact us: info@nemesida-waf.com\033[0m"
  exit 1
fi

## Processing the params
for i in "$@"; do
  case $i in
    pg_api_pwd=*)
      pg_api_pwd="${i#*=}"
      shift
      ;;
    pg_cabinet_pwd=*)
      pg_cabinet_pwd="${i#*=}"
      shift
      ;;
    api_srv_ip=*)
      api_srv_ip="${i#*=}"
      shift
      ;;
    *)
      ;;
  esac
done

## Parameters validation
if [ -z "$pg_api_pwd" ]; then echo -e "\033[0;101mERROR: pg_api_pwd parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$pg_cabinet_pwd" ]; then echo -e "\033[0;101mERROR: pg_cabinet_pwd parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$api_srv_ip" ]; then echo -e "\033[0;101mERROR: api_srv_ip parameter is missing\033[0m" ; exit 1 ; fi

## Display the applied parameters
echo "Database password for user nw_api: $pg_api_pwd"
echo "Database password for user nw_cabinet: $pg_cabinet_pwd"
echo "Nemesida WAF API IP: $api_srv_ip"

## Parameters confirmation
while [ "$ask" != "y" ]
do
  read -p "Continue? [y/n]: " ask
  ask=$(echo $ask | tr '[:upper:]' '[:lower:]')
done

##
# System update
##

echo "System update"

if [[ "$os_base" =~ debian|ubuntu ]]
then
  (apt-get update -qq && apt-get upgrade -qqy) || (echo -e "\033[0;101mERROR: update system is failed\033[0m"; exit 1)
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  setenforce 0
  echo -e "SELINUX=disabled\nSELINUXTYPE=targeted" > /etc/selinux/config
  (dnf update -qqy) || (echo -e "\033[0;101mERROR: update system is failed\033[0m"; exit 1)
fi

##
# PostgreSQL
##

echo "Setting up PostgreSQL"

if [[ "$os_base" =~ debian|ubuntu ]]
then
  (apt-get install postgresql -qqy) ||  (echo -e "\033[0;101mERROR: install PostgreSQL is failed\033[0m"; exit 1)
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  (dnf install postgresql-devel postgresql-server -qqy) || (echo -e "\033[0;101mERROR: install PostgreSQL is failed\033[0m"; exit 1)
  (postgresql-setup initdb) || (echo -e "\033[0;101mERROR: PostgreSQL initialization is failed\033[0m"; exit 1)
fi

postgres_version=$(ls /usr/lib/postgresql/ | grep -P '^\d+$' | sort -n | tail -1)
sleep 10

if [[ "$os_base" =~ debian|ubuntu ]]
then
  cat /etc/postgresql/$postgres_version/main/pg_hba.conf | grep -q "host all all $api_srv_ip/32 md5" || sed -i "/# IPv4 local connections:/a host all all $api_srv_ip/32 md5" /etc/postgresql/$postgres_version/main/pg_hba.conf
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  sed -i -r 's|host\s+all\s+all\s+127.0.0.1/32\s+ident|host all all 127.0.0.1/32 md5|' /var/lib/pgsql/data/pg_hba.conf
  sed -i -r 's|host\s+all\s+all\s+::1/128\s+ident|host all all ::1/128 md5|' /var/lib/pgsql/data/pg_hba.conf
  cat /var/lib/pgsql/data/pg_hba.conf | grep -q "host all all $api_srv_ip/32 md5" || sed -i "/# IPv4 local connections:/a host all all $api_srv_ip/32 md5" /var/lib/pgsql/data/pg_hba.conf
fi

systemctl reenable postgresql
systemctl start postgresql
(netstat -lnp | grep -q ':5432') || (echo -e "\033[0;101mERROR: start PostgreSQL is failed\033[0m"; exit 1)

##
# Create the databases
##

echo "Creating databases"

su - postgres -c "psql -c \"CREATE DATABASE waf;\""
su - postgres -c "psql -c \"CREATE ROLE nw_api PASSWORD '$pg_api_pwd';\""
su - postgres -c "psql -c \"GRANT ALL ON DATABASE waf TO nw_api;\""
su - postgres -c "psql -c \"ALTER ROLE nw_api WITH LOGIN;\""
su - postgres -c "psql waf -c \"GRANT ALL ON ALL TABLES IN SCHEMA public TO nw_api;\""
su - postgres -c "psql waf -c \"GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO nw_api;\""
su - postgres -c "psql waf -c \"GRANT CREATE ON SCHEMA public TO nw_api;\""

#

su - postgres -c "psql -c \"CREATE DATABASE cabinet;\""
su - postgres -c "psql -c \"CREATE ROLE nw_cabinet PASSWORD '$pg_cabinet_pwd';\""
su - postgres -c "psql -c \"GRANT ALL ON DATABASE cabinet TO nw_cabinet;\""
su - postgres -c "psql -c \"ALTER ROLE nw_cabinet WITH LOGIN;\""
su - postgres -c "psql cabinet -c \"GRANT ALL ON ALL TABLES IN SCHEMA public TO nw_cabinet;\""
su - postgres -c "psql cabinet -c \"GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO nw_cabinet;\""
su - postgres -c "psql cabinet -c \"GRANT CREATE ON SCHEMA public TO nw_cabinet;\""
