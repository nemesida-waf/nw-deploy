#!/bin/bash

## Settings
for i in "$@"; do
  case $i in
    -nw_api_password=*)
      nw_api_password="${i#*=}"
      shift
      ;;
    -nw_cabinet_password=*)
      nw_cabinet_password="${i#*=}"
      shift
      ;;
    -API_server=*)
      API_server="${i#*=}"
      shift
      ;;
    -*|--*)
      echo "Unknown option $i"
      exit 1
      ;;
    *)
      ;;
  esac
done

if [ -z "$nw_api_password" ]; then read -t 30 -p "Enter a nw_api user password: " nw_api_password ; fi
if [ -z "$nw_cabinet_password" ]; then read -t 30 -p "Enter a nw_cabinet user password: " nw_cabinet_password ; fi
if [ -z "$API_server" ]; then read -t 30 -p "Enter a Nemesida WAF API server IP: " API_server ; fi

## OS detection
os_base=$(cat /etc/os-release | grep -E '^ID=' | awk '{print $2}' FS="=")
postgres_version=$(dpkg -l | grep -E 'postgres' | head -n 1 | awk '{print $3}' | cut -b 1-2)

## Update
if [[ "$os_base" == "debian"  || "$os_base" == "ubuntu" ]]
then
  (apt-get update -qq && apt-get upgrade -qqy) || (echo -e "\033[0;101mAn error occured while update system\033[0m"; exit 1)
elif [[ "$os_base" == "centos"  || "$os_base" == "red hat" ]]
then
  setenforce 0 > /dev/null 2>&1
  echo -e "SELINUX=disabled\nSELINUXTYPE=targeted" > /etc/selinux/config
  (dnf update -qqy) || (echo -e "\033[0;101mAn error occured while upgrade system\033[0m"; exit 1)
fi

## PostgreSQL install
if [[ "$os_base" == "debian"  || "$os_base" == "ubuntu" ]]
then
  (apt-get install postgresql -qqy) ||  (echo -e "\033[0;101mAn error occured while installing PostgreSQL\033[0m"; exit 1)
  sed -i "/# IPv4 local connections:/ a \host all all $API_server md5" /etc/postgresql/$postgres_version/main/pg_hba.conf
elif [[ "$os_base" == "centos"  || "$os_base" == "red hat" ]]
then
  (dnf install postgresql-devel postgresql-server -qqy) || (echo -e "\033[0;101mAn error occured while installing PostgreSQL\033[0m"; exit 1)
  (postgresql-setup initdb) || (echo -e "\033[0;101mAn error occurred while initializing PostgreSQL\033[0m"; exit 1)
  sed -i -r 's|host\s+all\s+all\s+127.0.0.1/32\s+ident|host all all 127.0.0.1/32 md5|' /var/lib/pgsql/data/pg_hba.conf
  sed -i -r 's|host\s+all\s+all\s+::1/128\s+ident|host all all ::1/128 md5|' /var/lib/pgsql/data/pg_hba.conf
  sed -i "/# IPv4 local connections:/ a \host all all $API_server md5" /var/lib/pgsql/data/pg_hba.conf
fi

systemctl reenable postgresql > /dev/null 2>&1
(netstat -lnp | grep -q ':5432') || (echo -e "\033[0;101mAn error occured while starting PostgreSQL\033[0m"; exit 1)

##
# Create databases
##

su - postgres -c "psql -c \"CREATE DATABASE waf;\""
su - postgres -c "psql -c \"CREATE ROLE nw_api PASSWORD '$nw_api_password';\""
su - postgres -c "psql -c \"GRANT ALL ON DATABASE waf TO nw_api;\""
su - postgres -c "psql -c \"ALTER ROLE nw_api WITH LOGIN;\""
su - postgres -c "psql waf -c \"GRANT ALL ON ALL TABLES IN SCHEMA public TO nw_api;\""
su - postgres -c "psql waf -c \"GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO nw_api;\""
su - postgres -c "psql waf -c \"GRANT CREATE ON SCHEMA public TO nw_api;\""

#

su - postgres -c "psql -c \"CREATE DATABASE cabinet;\""
su - postgres -c "psql -c \"CREATE ROLE nw_cabinet PASSWORD '$nw_cabinet_password';\""
su - postgres -c "psql -c \"GRANT ALL ON DATABASE cabinet TO nw_cabinet;\""
su - postgres -c "psql -c \"ALTER ROLE nw_cabinet WITH LOGIN;\""
su - postgres -c "psql cabinet -c \"GRANT ALL ON ALL TABLES IN SCHEMA public TO nw_cabinet;\""
su - postgres -c "psql cabinet -c \"GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO nw_cabinet;\""
su - postgres -c "psql cabinet -c \"GRANT CREATE ON SCHEMA public TO nw_cabinet;\""


