#!/bin/bash

##
# Example of use:
# /bin/bash ./4-filtering-node-deploy.sh 'nwaf_lic_key=1234567890' 'api_url=http(s)://api.example.com:8080/nw-api/' 'sys_proxy=http(s)://proxy.example.com:3128' 'api_proxy=http(s)://proxy.example.com:3128'
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
    nwaf_lic_key=*)
      nwaf_lic_key="${i#*=}"
      shift
      ;;
    api_url=*)
      api_url="${i#*=}"
      shift
      ;;
    sys_proxy=*)
      sys_proxy="${i#*=}"
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
if [ -z "$nwaf_lic_key" ]; then echo -e "\033[0;101mERROR: nwaf_lic_key parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$api_url" ]; then echo -e "\033[0;101mERROR: api_url parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$rmq_user" ]; then echo -e "\033[0;101mERROR: rmq_user parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$rmq_pwd" ]; then echo -e "\033[0;101mERROR: rmq_pwd parameter is missing\033[0m" ; exit 1 ; fi

if [ -z "$sys_proxy" ]; then sys_proxy=none; fi
if [ -z "$api_proxy" ]; then api_proxy=none; fi

## Display the applied parameters
echo "Nemesida WAF license key: $nwaf_lic_key"
echo "Nemesida WAF API server URL: $api_url"
echo "RabbitMQ user for connection to the filtering node: $rmq_user"
echo "RabbitMQ password for connection to the filtering node: $rmq_pwd"
echo "System proxy (if used): $sys_proxy"
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

echo "Add Nginx web server repository"

if [[ "$os_base" =~ debian|ubuntu ]]
then
  apt-get update -qqy
  apt-get install -qqy apt-transport-https gnupg2 curl
  echo "deb http://nginx.org/packages/$os_base/ $os_code_name nginx" > /etc/apt/sources.list.d/nginx.list
  curl -s https://nginx.org/keys/nginx_signing.key | gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/trusted.gpg --import
  chmod 644 /etc/apt/trusted.gpg.d/trusted.gpg
  apt-get update -qqy
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  echo -e "[nginx-stable]\nname=nginx stable repo\nbaseurl=http://nginx.org/packages/rhel/\$releasever/\$basearch/\ngpgkey=https://nginx.org/keys/nginx_signing.key\nenabled=1\ngpgcheck=1\nmodule_hotfixes=true" > /etc/yum.repos.d/nginx.repo
  dnf update -qqy
fi

echo "Add Nemesida WAF repository"

if [[ "$os_base" == debian ]]
then
  apt-get update -qqy
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
  dnf install -qqy epel-release
  dnf update -qqy
fi

## RabbitMQ RPM specification
rabbitmq_asc_url=$(curl https://www.rabbitmq.com/docs/install-rpm#red-hat-8-centos-stream-8-modern-fedora-releases -A 'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0' | grep -E 'https://github.com/rabbitmq/rabbitmq-server/releases/download/' | awk -F '["]' '{print $4}')
rabbitmq_rpm_url=$(curl https://www.rabbitmq.com/docs/install-rpm#red-hat-8-centos-stream-8-modern-fedora-releases -A 'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0' | grep -E 'https://github.com/rabbitmq/rabbitmq-server/releases/download/' | awk -F '["]' '{print $2}')
rabbitmq_rpm_name=$(curl https://www.rabbitmq.com/docs/install-rpm#red-hat-8-centos-stream-8-modern-fedora-releases -A 'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0' | grep -E 'https://github.com/rabbitmq/rabbitmq-server/releases/download/' | awk -F '["]' '{print $2}' | awk -F [/] '{print $9}')

##
# Update the system
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
# Web server
##

echo "Setting up web server"

if [[ "$os_base" =~ debian|ubuntu ]]
then
  apt-get update -qqy
  apt-get install -qqy nginx
  nginx_version=$(dpkg -l | grep nginx | awk '{print $3}' | cut -c 1-4 | sort -u)
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  dnf update -qqy
  dnf install -qqy nginx
  nginx_version=$(rpm -q nginx | cut -c 7-10)
fi

##
# Install the packages
##

echo "Setting up Nemesida WAF Filtering node"

rm -f /etc/machine-id
/bin/systemd-machine-id-setup

if [[ "$os_base" == debian ]]
then
  apt-get install -qqy python3 python3-venv python3-pip python3-dev python3-setuptools librabbitmq4 libcurl3-gnutls libcurl4-openssl-dev libc6-dev gcc g++ memcached rabbitmq-server
  (netstat -lnp | grep -q ':5672') || (echo -e "\033[0;101mERROR: start RabbitMQ server is failed\033[0m"; exit 1)
  apt-get install -qqy nwaf-dyn-$nginx_version
elif [[ "$os_base" == ubuntu ]]
then
  if [[ "$os_code_name" == focal ]]
  then
    apt-get install -qqy python3.9 python3.9-venv python3-pip python3.9-dev python3-setuptools libcurl3-gnutls librabbitmq4 libcurl4-openssl-dev libc6-dev gcc g++ memcached rabbitmq-server
  elif [[ "$os_code_name" =~ jammy|noble ]]
  then
    apt-get install -qqy python3 python3-venv python3-pip python3-dev python3-setuptools libcurl3-gnutls librabbitmq4 libcurl4-openssl-dev libc6-dev gcc g++ memcached rabbitmq-server
  fi
  (netstat -lnp | grep -q ':5672') || (echo -e "\033[0;101mERROR: start RabbitMQ server is failed\033[0m"; exit 1)
  apt-get install -qqy nwaf-dyn-$nginx_version
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  dnf install -qqy epel-release
  dnf update -qqy
  rpm --import $rabbitmq_asc_url
  dnf install -qqy socat logrotate
  curl -L $rabbitmq_rpm_url -o /tmp/$rabbitmq_rpm_name
  dnf install -qqy /tmp/$rabbitmq_rpm_name
  systemctl reenable rabbitmq-server
  systemctl restart rabbitmq-server
  (netstat -lnp | grep -q ':5672') || (echo -e "\033[0;101mERROR: start RabbitMQ server is failed\033[0m"; exit 1)
  rm /tmp/$rabbitmq_rpm_name
  if [[ "$os_version" == 8 ]]
  then
    dnf update -qqy
    dnf install -qqy epel-release
    dnf config-manager --set-enabled powertools
    dnf install -qqy python39 python39-devel python39-setuptools python39-pip systemd openssl librabbitmq libcurl-devel gcc memcached
  elif [[ "$os_version" == 9 ]]
  then
    dnf update -qqy
    dnf install -qqy epel-release
    dnf config-manager --set-enabled crb
    dnf install -qqy python3 python3-devel python3-setuptools python3-pip systemd openssl librabbitmq libcurl-devel gcc memcached
  fi
  dnf install -qqy nwaf-dyn-$nginx_version
fi

## Enable the dynamic module
sed -i '/^user/i load_module \/etc\/nginx\/modules\/ngx_http_waf_module.so;' /etc/nginx/nginx.conf
sed -i '/http {/a \    ##\n    # Nemesida WAF\n    ##\n\n    ## Request body is too large fix\n    client_body_buffer_size 25M;\n\n    include \/etc\/nginx\/nwaf\/conf\/global\/*.conf;' /etc/nginx/nginx.conf

## Update the settings
sed -i "s|nwaf_license_key none|nwaf_license_key $nwaf_lic_key|" /etc/nginx/nwaf/conf/global/nwaf.conf
sed -i "s|nwaf_sys_proxy none|nwaf_sys_proxy $sys_proxy|" /etc/nginx/nwaf/conf/global/nwaf.conf
sed -i "s|nwaf_api_proxy none|nwaf_api_proxy $api_proxy|" /etc/nginx/nwaf/conf/global/nwaf.conf
sed -i "s|nwaf_api_conf host=none|nwaf_api_conf host=$api_url|" /etc/nginx/nwaf/conf/global/nwaf.conf

## Restart the services
systemctl restart nginx rabbitmq-server memcached nwaf_update mla_main api_firewall
