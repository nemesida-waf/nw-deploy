#!/bin/bash

##
# Example of use:
# /bin/bash ./2-api-deploy.sh 'timezone=Europe/Moscow' 'pg_srv_ip=1.1.1.1' 'pg_srv_port=5432' 'pg_api_pwd=YOUR_PASSWORD' 'api_proxy=http(s)://proxy.example.com:3128'
##

## OS detection
os_base=$(cat /etc/os-release | grep -E '^ID=' | awk '{print $2}' FS="=" | tr -d '"')
os_version=$(cat /etc/os-release | grep -E '^VERSION_ID=' | awk '{print $2}' FS="=" | tr -d '"' | grep -o '^[^.]*')
os_code_name=$(cat /etc/os-release | grep -E '^VERSION_CODENAME=' | awk '{print $2}' FS="=" | tr -d '"')

if ! [[ "$os_base" =~ debian|ubuntu|rhel|centos|rocky ]]
then
  echo -e "\033[0;101mUnsupported operating system. Please, contact us: info@nemesida-waf.com\033[0m"
  exit 1
fi

## Processing the params
for i in "$@"; do
  case $i in
    timezone=*)
      timezone="${i#*=}"
      shift
      ;;
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
    api_proxy=*)
      api_proxy="${i#*=}"
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

## Display the applied parameters
echo "Time Zone: $timezone"
echo "PostgreSQL IP: $pg_srv_ip"
echo "PostgreSQL port: $pg_srv_port"
echo "Database password for user nw_api: $pg_api_pwd"
echo "Nemesida WAF API proxy (if used): $api_proxy"

## Parameters confirmation
while [ "$ask" != "y" ]
do
  read -p "Continue? [y/n]: " ask
  ask=$(echo $ask | tr '[:upper:]' '[:lower:]')
done

##
# Connect the repository
##

echo "Add Nemesida WAF repository"

if [[ "$os_base" == debian ]]
then
  apt-get update -qqy
  apt-get install -qqy apt-transport-https gnupg2 curl
  if [[ "$os_code_name" =~ bookworm|trixie ]]
  then
    echo "deb https://repo.s.nemesida-waf.ru/debian $os_code_name nwaf" > /etc/apt/sources.list.d/NemesidaWAF.list
  fi
  curl -s https://repo.s.nemesida-waf.ru/gpg.key | gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/trusted.gpg --import
  chmod 644 /etc/apt/trusted.gpg.d/trusted.gpg
  apt-get update -qqy
elif [[ "$os_base" == ubuntu ]]
then
  apt-get update -qqy
  apt-get install -qqy apt-transport-https gnupg2 curl
  if [[ "$os_code_name" == jammy ]]
  then
    echo "deb [arch=amd64] https://repo.s.nemesida-waf.ru/ubuntu $os_code_name non-free" > /etc/apt/sources.list.d/NemesidaWAF.list
  elif [[ "$os_code_name" == noble ]]
  then
    echo "deb [arch=amd64] https://repo.s.nemesida-waf.ru/ubuntu $os_code_name nwaf" > /etc/apt/sources.list.d/NemesidaWAF.list
  elif [[ "$os_code_name" == resolute ]]
  then
    echo "deb [arch=amd64] https://repo.s.nemesida-waf.ru/ubuntu $os_code_name nwaf" > /etc/apt/sources.list.d/NemesidaWAF.list
  fi
  curl -s https://repo.s.nemesida-waf.ru/gpg.key | gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/trusted.gpg --import
  chmod 644 /etc/apt/trusted.gpg.d/trusted.gpg
  apt-get update -qqy
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  echo -e "[NemesidaWAF]\nname=Nemesida WAF Packages for RHEL\nbaseurl=https://repo.s.nemesida-waf.ru/rhel/\$releasever/\$basearch/\ngpgkey=https://repo.s.nemesida-waf.ru/gpg.key\nenabled=1\ngpgcheck=1" > /etc/yum.repos.d/NemesidaWAF.repo
  dnf install -qqy epel-release
  dnf update -qqy
fi

##
# Update the system
##

echo "System update"

timedatectl set-ntp yes
timedatectl set-timezone $timezone

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
# Install the packages
##

echo "Setting up Nemesida WAF API"

if [[ "$os_base" =~ debian|ubuntu ]]
then
  apt-get install -qqy nwaf-api
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  dnf install -qqy epel-release
  dnf update -qqy
  if [[ "$os_version" =~ 8|9|10 ]]
  then
    dnf install -qqy nwaf-api
  fi
fi

## Update the settings
sed -i "s|DB_HOST = '127.0.0.1'|DB_HOST = '$pg_srv_ip'|" /var/www/nw-api/settings.py
sed -i "s|DB_PORT = '5432'|DB_PORT = '$pg_srv_port'|" /var/www/nw-api/settings.py
sed -i "s|DB_PASS = ''|DB_PASS = '$pg_api_pwd'|" /var/www/nw-api/settings.py
sed -i "s|PROXY = ''|PROXY = '$api_proxy'|" /var/www/nw-api/settings.py

## Start the Nginx
mv /etc/nginx/conf.d/nwaf-api.conf.disabled /etc/nginx/conf.d/nwaf-api.conf
nginx -t && service nginx reload
(netstat -lnp | grep -q ':8080') || (echo -e "\033[0;101mERROR: start Nemesida WAF API is failed\033[0m"; exit 1)

## Restart the services
systemctl restart nw-api rldscupd nginx memcached
