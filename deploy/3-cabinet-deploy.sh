#!/bin/bash

##
# Example of use:
# /bin/bash ./3-cabinet-deploy.sh 'pg_srv_ip=xxx' 'pg_srv_port=xxx' 'pg_api_pwd=x.x.x.x' 'pg_cabinet_pwd=x.x.x.x' 'api_srv_ip=x.x.x.x' 'proxy=xxx:xx'
##

## OS detection
os_base=$(cat /etc/os-release | grep -E '^ID=' | awk '{print $2}' FS="=" | tr -d '"')
os_version=$(cat /etc/os-release | grep -E '^VERSION_ID=' | awk '{print $2}' FS="=" | tr -d '"' | grep -o '^[^.]*')
os_code_name=$(cat /etc/os-release | grep -E '^VERSION_CODENAME=' | awk '{print $2}' FS="=" | tr -d '"')

## Set environment timezone
timedatectl set-timezone Europe/Moscow
echo 'Europe/Moscow' > /etc/timezone


if ! [[ "$os_base" =~ debian|ubuntu|rhel|centos|rocky ]]
then
  echo -e "\033[0;101mUnsupported operating system. Please, contact us: info@nemesida-waf.com\033[0m"
  exit 1
fi

## Processing the params
for i in "$@"; do
  case $i in
    pg_srv_ip=*)
      pg_srv_ip="${i#*=}"
      shift
      ;;
    pg_srv_port=*)
      pg_srv_port="${i#*=}"
      shift
      ;;
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
    proxy=*)
     proxy="${i#*=}"
      shift
      ;;
    *)
      ;;
  esac
done

## Parameters validation
if [ -z "$pg_srv_ip" ]; then echo -e "\033[0;101mERROR: pg_srv_ip parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$pg_srv_port" ]; then echo -e "\033[0;101mERROR: pg_srv_port parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$pg_api_pwd" ]; then echo -e "\033[0;101mERROR: pg_api_pwd parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$pg_cabinet_pwd" ]; then echo -e "\033[0;101mERROR: pg_cabinet_pwd parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$api_srv_ip" ]; then echo -e "\033[0;101mERROR: api_srv_ip parameter is missing\033[0m" ; exit 1 ; fi

## Display the applied parameters
echo "PostgreSQL IP: $pg_srv_ip"
echo "PostgreSQL port: $pg_srv_port"
echo "Database password for user nw_api: $pg_api_pwd"
echo "Database password for user nw_cabinet: $pg_cabinet_pwd"
echo "Nemesida WAF API IP: $api_srv_ip"
echo "System proxy (if used): $proxy"

## Parameters confirmation
while [ "$ask" != "y" ]
do
  read -p "Continue? [y/n]: " ask
  ask=$(echo $ask | tr '[:upper:]' '[:lower:]')
done

##
# Nemesida WAF repository
##

echo "Add Nemesida WAF repository"

if [[ "$os_base" == debian ]]
then
  apt-get update -qqy
  apt-get install apt-transport-https gnupg2 curl -qqy
  if [[ "$os_code_name" == bullseye ]]
  then
    echo "deb https://nemesida-security.com/repo/nw/debian $os_code_name non-free" > /etc/apt/sources.list.d/NemesidaWAF.list
  elif [[ "$os_code_name" == bookworm ]]
  then
    echo "deb https://nemesida-security.com/repo/nw/debian $os_code_name nwaf" > /etc/apt/sources.list.d/NemesidaWAF.list
  fi
  curl -s https://nemesida-security.com/repo/nw/gpg.key | gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/trusted.gpg --import
  chmod 644 /etc/apt/trusted.gpg.d/trusted.gpg
  apt-get update -qqy
elif [[ "$os_base" == ubuntu ]]
then
  apt-get update -qqy
  apt-get install apt-transport-https gnupg2 curl -qqy
  if [[ "$os_code_name" =~ focal|jammy ]]
  then
    echo "deb [arch=amd64] https://nemesida-security.com/repo/nw/ubuntu $os_code_name non-free" > /etc/apt/sources.list.d/NemesidaWAF.list
  elif [[ "$os_code_name" == noble ]]
  then
    echo "deb [arch=amd64] https://nemesida-security.com/repo/nw/ubuntu $os_code_name nwaf" > /etc/apt/sources.list.d/NemesidaWAF.list
  fi
  curl -s https://nemesida-security.com/repo/nw/gpg.key | gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/trusted.gpg --import
  chmod 644 /etc/apt/trusted.gpg.d/trusted.gpg
  apt-get update -qqy
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  echo -e "[NemesidaWAF]\nname=Nemesida WAF Packages for RHEL\nbaseurl=https://nemesida-security.com/repo/nw/rhel/\$releasever/\$basearch/\ngpgkey=https://nemesida-security.com/repo/nw/gpg.key\nenabled=1\ngpgcheck=1" > /etc/yum.repos.d/NemesidaWAF.repo
  dnf install epel-release -qqy
  dnf update -qqy
fi

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
# Nemesida WAF API
##

echo "Setting up Nemesida WAF Cabinet"

if [[ "$os_base" == debian ]]
then
  apt-get install nginx python3 python3-venv python3-dev python3-reportbug python3-pip memcached libmemcached-dev postgresql-server-dev-all gettext libpcre3-dev pkg-config libcairo2-dev -qqy
  apt-get install nwaf-cabinet -qqy
elif [[ "$os_base" == ubuntu ]]
then
  if [[ "$os_code_name" == focal ]]
  then
    apt-get install nginx python3.9 python3.9-venv build-essential python3.9-dev python3.9-reportbug python3-pip memcached libmemcached-dev libpq-dev gettext libpcre3-dev pkg-config libcairo2-dev -qqy
  elif [[ "$os_code_name" =~ jammy|noble ]]
  then
    apt-get install nginx python3 python3-venv build-essential python3-dev python3-reportbug python3-pip memcached libmemcached-dev libpq-dev gettext libpcre3-dev pkg-config libcairo2-dev -qqy
  fi
  apt-get install nwaf-cabinet -qqy
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  dnf install epel-release -qqy
  dnf update -qqy
  if [[ "$os_version" == 8 ]]
  then
    dnf install nginx python39 python39-devel python39-setuptools python39-pip gcc memcached postgresql-devel gettext pcre-devel pkg-config cairo-devel -qqy
  elif [[ "$os_version" == 9 ]]
  then
    dnf install nginx python3 python3-devel python3-setuptools python3-pip gcc memcached postgresql-devel gettext pcre-devel pkg-config cairo-devel -qqy
  fi
  dnf install nwaf-cabinet -qqy
fi

## Configure Nemesida WAF Cabinet settings file
sed -i "s|HTTP_PROXY_CONF = ''|HTTP_PROXY_CONF = '$proxy'|" /var/www/app/cabinet/settings.py
sed -i "s|DB_HOST_CABINET = ''|DB_HOST_CABINET = '$pg_srv_ip'|" /var/www/app/cabinet/settings.py
sed -i "s|DB_PORT_CABINET = ''|DB_PORT_CABINET = '$pg_srv_port'|" /var/www/app/cabinet/settings.py
sed -i "s|DB_PASS_CABINET = ''|DB_PASS_CABINET = '$pg_cabinet_pwd'|" /var/www/app/cabinet/settings.py
sed -i "s|DB_HOST_CONF = ''|DB_HOST_CONF = '$pg_srv_ip'|" /var/www/app/cabinet/settings.py
sed -i "s|DB_PORT_CONF = ''|DB_PORT_CONF = '$pg_srv_port'|" /var/www/app/cabinet/settings.py
sed -i "s|DB_PASS_CONF = ''|DB_PASS_CONF = '$pg_api_pwd'|" /var/www/app/cabinet/settings.py
sed -i "s|localhost|$api_srv_ip|g" /var/www/app/cabinet/settings.py

## Apply mirgation and create superuser
cd /var/www/app/ && . venv/bin/activate && python3 manage.py check_migrations && python3 manage.py migrate && python3 manage.py createsuperuser && deactivate

## Start Nemesida WAF Cabinet service
mv /etc/nginx/conf.d/cabinet.conf.disabled /etc/nginx/conf.d/cabinet.conf
nginx -t && service nginx reload
(netstat -lnp | grep -q ':80') || (echo -e "\033[0;101mERROR: start Nemesida WAF Cabinet is failed\033[0m"; exit 1)
systemctl restart nginx cabinet cabinet_ipinfo cabinet_attack_notification cabinet_cleaning_db cabinet_rule_update memcached

