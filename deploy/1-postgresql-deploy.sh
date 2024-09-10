#!/bin/bash

#for i in "$@"
#do
#case $i in
#    nw_api_password="$2")
#    nw_api_password="";
#    shift
#    ;;
#    nw_cabinet_password=)
#    nw_cabinet_password="${i#*=}"
#    ;;
#    API_server_IP=)
#    API_server_IP="${i#*=}"
#    ;;
#    *)
#    ;;
#esac
#done


while [ "$#" -gt 0 ]; do
  case "$1" in
    nw_api_password) nw_api_password="${1#*=}"; shift 1;;
    nw_cabinet_password) nw_cabinet_password="${1#*=}"; shift 1;;
    API_server_IP) API_server_IP="${1#*=}"; shift 1;;
    nw_api_password|nw_cabinet_password|API_server_IP) echo "$1 requires an argument" >&2; exit 1;;
    
    -*) echo "unknown option: $1" >&2; exit 1;;
    *) handle_argument "$1"; shift 1;;
  esac
done



#while [[ "$#" -gt 0 ]]; do
#    case $1 in
#        nw_api_password=*) nw_api_password="$2" ; shift ;;
#        nw_cabinet_password=*) nw_cabinet_password="$3" ; shift;;
#        API_server_IP=*) API_server_IP="$4" ;;
#        *) echo "Unknown parameter passed: $1"; exit 1 ;;
#    esac
#    shift
#done

echo "nw_api_password parameter is missed"
echo "nw_cabinet_password parameter is missed"
echo "Nemesida WAF API server IP is missed"

read -t 30 -p "Enter a nw_api user password: " nw_api_password
read -t 30 -p "Enter a nw_cabinet user password: " nw_cabinet_password
read -t 30 -p "Enter a Nemesida WAF API server IP: " API_server_IP

echo $2
echo $3
echo $4
## Settings

## OS detection
os_base=$(cat /etc/os-release | grep -E '^ID=' | awk '{print $2}' FS="=" | tr -d '"' | head -c 1)
os_vers=$(cat /etc/os-release | grep -E '^VERSION_ID=' | awk '{print $2}' FS="=" | tr -d '"' | awk '{print $1}' FS=".")

## Netstat
netstat="netstat -nlp"

## Update
if [[ "$os_base" == "d"  || "$os_base" == "u" ]]
then
  (apt-get update > /dev/null 2>&1) || (echo "An error occure while update system"; exit 1)
  (apt-get upgarde -qqy) || (echo "An error occure while upgrade system"; exit 1)
elif [[ "$os_base" == "c"  || "$os_base" == "r" ]]
then
  setenforce 0 > /dev/null 2>&1
  echo -e "SELINUX=disabled\nSELINUXTYPE=targeted" > /etc/selinux/config
  (dnf update -qqy) || (echo "Error occure while upgrade system"; exit 1)
fi

## PostgreSQL install
if [[ "$os_base" == "d"  || "$os_base" == "u" ]]
then
  (apt-get install postgresql -qqy) ||  (echo "An error occure while installing PostgreSQL"; exit 1)
  systemctl reenable postgresql > /dev/null 2>&1
  ($netstat | grep -q ':5438') || (echo "An error occure while starting PostgreSQL"; exit 1)
elif [[ "$os_base" == "c"  || "$os_base" == "r" ]]
then
  (dnf install postgresql-devel postgresql-server -qqy) || (echo "An error occure while installing PostgreSQL"; exit 1)
  (postgresql-setup initdb) || (echo "An error occurred while initializing PostgreSQL"; exit 1)
  sed -i "s|host all all 127.0.0.1/32 ident|host all all 127.0.0.1/32 md5|" /var/lib/pgsql/data/pg_hba.conf
  sed -i "s|host all all ::1/128 ident|host all all ::1/128 md5|" /var/lib/pgsql/data/pg_hba.conf
  systemctl reenable postgresql > /dev/null 2>&1
  ($netstat | grep -q ':5432') || (echo "Error occure while starting PostgreSQL"; exit 1)
fi

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

