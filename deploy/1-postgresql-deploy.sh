#!/bin/bash

## Settings
nw_api_password=""
nw_cabinet_password=""

## OS detection
os_base=$(cat /etc/os-release | grep -E '^ID=' | awk '{print $2}' FS="=" | tr -d '"' | head -c 1)
os_vers=$(cat /etc/os-release | grep -E '^VERSION_ID=' | awk '{print $2}' FS="=" | tr -d '"' | awk '{print $1}' FS=".")

## Netstat
netstat="netstat -nlp"

## Update
if [[ "$os_base" == "d"  || "$os_base" == "u" ]]
then
  (apt update > /dev/null 2>&1) || (apt upgrade -y > /dev/null 2>&1)
elif [[ "$os_base" == "c"  || "$os_base" == "r" ]]
then
  setenforce 0 > /dev/null 2>&1
  echo -e "SELINUX=enforcing\nSELINUX=disabled" > /etc/selinux/config
  dnf update -y > /dev/null 2>&1
fi

## PostgreSQL install
if [[ "$os_base" == "d"  || "$os_base" == "u" ]]
then
  apt install postgresql -y > /dev/null 2>&1
  (systemctl start postgresql > /dev/null 2>&1) || (systemctl enable postgresql > /dev/null 2>&1)
  ($netstat | grep -q ':5432')
elif [[ "$os_base" == "c"  || "$os_base" == "r" ]]
then
  (dnf install postgresql-devel postgresql-server > /dev/null 2>&1) || (postgresql-setup initdb > /dev/null 2>&1) 
  sleep 10
  sed -i -r 's|host\s+all\s+all\s+127.0.0.1/32\s+ident|host all all 127.0.0.1/32 md5|' /var/lib/pgsql/data/pg_hba.conf
  sed -i -r 's|host\s+all\s+all\s+::1/128\s+ident|host all all ::1/128 md5|' /var/lib/pgsql/data/pg_hba.conf
  (systemctl start postgresql > /dev/null 2>&1) || (systemctl enable postgresql > /dev/null 2>&1)
  ($netstat | grep -q ':5432')
fi

##
# Create databases
##

su - postgres -c "psql -c \"CREATE DATABASE waf;\"" > /dev/null 2>&1
su - postgres -c "psql -c \"CREATE ROLE nw_api PASSWORD '$nw_api_password';\"" > /dev/null 2>&1
su - postgres -c "psql -c \"GRANT ALL ON DATABASE waf TO nw_api;\"" > /dev/null 2>&1
su - postgres -c "psql -c \"ALTER ROLE nw_api WITH LOGIN;\"" > /dev/null 2>&1
su - postgres -c "psql waf -c \"GRANT ALL ON ALL TABLES IN SCHEMA public TO nw_api;\"" > /dev/null 2>&1
su - postgres -c "psql waf -c \"GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO nw_api;\"" > /dev/null 2>&1
su - postgres -c "psql waf -c \"GRANT CREATE ON SCHEMA public TO nw_api;\"" > /dev/null 2>&1

#

su - postgres -c "psql -c \"CREATE DATABASE cabinet;\"" > /dev/null 2>&1
su - postgres -c "psql -c \"CREATE ROLE nw_cabinet PASSWORD '$nw_cabinet_password';\"" > /dev/null 2>&1
su - postgres -c "psql -c \"GRANT ALL ON DATABASE cabinet TO nw_cabinet;\"" > /dev/null 2>&1
su - postgres -c "psql -c \"ALTER ROLE nw_cabinet WITH LOGIN;\"" > /dev/null 2>&1
su - postgres -c "psql cabinet -c \"GRANT ALL ON ALL TABLES IN SCHEMA public TO nw_cabinet;\"" > /dev/null 2>&1
su - postgres -c "psql cabinet -c \"GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO nw_cabinet;\"" > /dev/null 2>&1
su - postgres -c "psql cabinet -c \"GRANT CREATE ON SCHEMA public TO nw_cabinet;\"" > /dev/null 2>&1
