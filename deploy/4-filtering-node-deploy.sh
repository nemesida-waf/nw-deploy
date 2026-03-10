#!/bin/bash

##
# Example of use:
# /bin/bash ./4-filtering-node-deploy.sh 'timezone=Europe/Moscow' 'nwaf_lic_key=1234567890' 'api_url=http(s)://api.example.com:8080/nw-api/' 'sys_proxy=http(s)://proxy.example.com:3128' 'api_proxy=http(s)://proxy.example.com:3128' 'websocket=yes' 'grpc=yes'
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
    websocket=*)
      websocket="${i#*=}"
      shift
      ;;
    grpc=*)
      grpc="${i#*=}"
      shift
      ;;
    *)
      ;;
  esac
done

## Parameters validation
if [ -z "$api_url" ]; then echo -e "\033[0;101mERROR: api_url parameter is missing\033[0m" ; exit 1 ; fi

if [ -z "$nwaf_lic_key" ]; then nwaf_lic_key=none; fi
if [ -z "$sys_proxy" ]; then sys_proxy=none; fi
if [ -z "$api_proxy" ]; then api_proxy=none; fi

## Display the applied parameters
echo "Time Zone: $timezone"
echo "Nemesida WAF license key: $nwaf_lic_key"
echo "Nemesida WAF API server URL: $api_url"
echo "System proxy (if used): $sys_proxy"
echo "Nemesida WAF API proxy (if used): $api_proxy"
echo "Use Websocket analysis module: $websocket"
echo "Use gRPC analysis module: $grpc"

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
  if [[ "$os_code_name" == jammy ]]
  then
    echo "deb [arch=amd64] https://repo.s.nemesida-waf.ru/ubuntu $os_code_name non-free" > /etc/apt/sources.list.d/NemesidaWAF.list
  elif [[ "$os_code_name" == noble ]]
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
# RabbitMQ
##

if [[ "$os_base" =~ rhel|centos|rocky ]]
then
  rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/rabbitmq-release-signing-key.asc'
  rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key'
  rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key'
  curl -s -L https://raw.githubusercontent.com/nemesida-waf/nw-deploy/refs/heads/main/misc/rhel-rmq.repo -o /etc/yum.repos.d/rabbitmq.repo
  dnf update -qqy
  dnf install -qqy socat logrotate
  dnf install -qqy erlang rabbitmq-server
  systemctl reenable rabbitmq-server
  systemctl restart rabbitmq-server
  (netstat -lnp | grep -q ':5672') || (echo -e "\033[0;101mERROR: start RabbitMQ server is failed\033[0m"; exit 1)
fi

##
# Install the packages
##

echo "Setting up Nemesida WAF Filtering node"

rm -f /etc/machine-id
/bin/systemd-machine-id-setup

if [[ "$os_base" =~ debian|ubuntu ]]
then
  apt-get install -qqy nwaf-dyn-$nginx_version
  (netstat -lnp | grep -q ':5672') || (echo -e "\033[0;101mERROR: start RabbitMQ server is failed\033[0m"; exit 1)
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  if [[ "$os_version" == 8 ]]
  then
    dnf update -qqy
    dnf install -qqy epel-release
    dnf config-manager --set-enabled powertools
  elif [[ "$os_version" =~ 9|10 ]]
  then
    dnf update -qqy
    dnf install -qqy epel-release
    dnf config-manager --set-enabled crb
  fi
  dnf install -qqy nwaf-dyn-$nginx_version
fi

## Enable the dynamic modules
sed -i '/^user/i load_module \/etc\/nginx\/modules\/ngx_http_waf_module.so;' /etc/nginx/nginx.conf
if [[ "$grpc" == yes ]]; then sed -i '/load_module \/etc\/nginx\/modules\/ngx_http_waf_module.so;/a \load_module /etc/nginx/modules/ngx_http_waf_grpc_module.so;' /etc/nginx/nginx.conf; fi
if [[ "$websocket" == yes ]]; then sed -i '/load_module \/etc\/nginx\/modules\/ngx_http_waf_module.so;/a \load_module /etc/nginx/modules/ngx_http_waf_ws_module.so;' /etc/nginx/nginx.conf; fi

## Request body is too large fix
sed -i '/http {/a \    ##\n    # Nemesida WAF\n    ##\n\n    proxy_busy_buffers_size 24k;\n    client_body_buffer_size 25M;\n    include \/etc\/nginx\/nwaf\/conf\/global\/*.conf;\n' /etc/nginx/nginx.conf

## Update the settings
sed -i "s|nwaf_license_key none|nwaf_license_key $nwaf_lic_key|" /etc/nginx/nwaf/conf/global/nwaf.conf
sed -i "s|nwaf_sys_proxy none|nwaf_sys_proxy $sys_proxy|" /etc/nginx/nwaf/conf/global/nwaf.conf
sed -i "s|nwaf_api_proxy none|nwaf_api_proxy $api_proxy|" /etc/nginx/nwaf/conf/global/nwaf.conf
sed -i "s|nwaf_api_conf host=none|nwaf_api_conf host=$api_url|" /etc/nginx/nwaf/conf/global/nwaf.conf

## Restart the services
systemctl restart nginx rabbitmq-server memcached nwaf_update mla_main api_firewall
