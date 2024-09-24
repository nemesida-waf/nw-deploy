#!/bin/bash

##
# Example of use:
# /bin/bash ./5-mlc-deploy.sh 'nwaf_lic_key=xxx' 'api_srv_ip=x.x.x.x' 'dyn_srv_ip=x.x.x.x' 'dyn_rmq_user=xxx' 'dyn_rmq_pwd=x.x.x.x' 'sys_proxy=xxx:xx' 'api_proxy=xxx:xx'
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
    api_srv_ip=*)
      api_srv_ip="${i#*=}"
      shift
      ;;
    dyn_srv_ip=*)
      dyn_srv_ip="${i#*=}"
      shift
      ;;
    dyn_rmq_user=*)
      dyn_rmq_user="${i#*=}"
      shift
      ;;
    dyn_rmq_pwd=*)
      dyn_rmq_pwd="${i#*=}"
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
if [ -z "$api_srv_ip" ]; then echo -e "\033[0;101mERROR: api_srv_ip parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$dyn_srv_ip" ]; then echo -e "\033[0;101mERROR: dyn_srv_ip parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$dyn_rmq_user" ]; then echo -e "\033[0;101mERROR: dyn_rmq_user parameter is missing\033[0m" ; exit 1 ; fi
if [ -z "$dyn_rmq_pwd" ]; then echo -e "\033[0;101mERROR: dyn_rmq_pwd parameter is missing\033[0m" ; exit 1 ; fi

## Display the applied parameters
echo "Nemesida WAF license key: $nwaf_lic_key"
echo "Nemesida WAF API server IP: $api_srv_ip"
echo "Filtering node server IP: $dyn_srv_ip"
echo "RabbitMQ user for connection to the filtering node: $dyn_rmq_user"
echo "RabbitMQ password for connection to the filtering node: $dyn_rmq_pwd"
echo "System proxy (if used): $sys_proxy"
echo "Nemesida WAF API proxy (if used): $api_proxy"

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
  apt-get install -qqy apt-transport-https gnupg2 curl
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
  apt-get install -qqy apt-transport-https gnupg2 curl
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
# Nemesida AI MLC
##

echo "Setting up Nemesida AI MLC"

rabbitmq_asc_url=$(curl https://www.rabbitmq.com/docs/install-rpm#red-hat-8-centos-stream-8-modern-fedora-releases -A 'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0' | grep -E 'https://github.com/rabbitmq/rabbitmq-server/releases/download/' | awk -F '["]' '{print $4}')
rabbitmq_rpm_url=$(curl https://www.rabbitmq.com/docs/install-rpm#red-hat-8-centos-stream-8-modern-fedora-releases -A 'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0' | grep -E 'https://github.com/rabbitmq/rabbitmq-server/releases/download/' | awk -F '["]' '{print $2}')
rabbitmq_rpm_name=$(curl https://www.rabbitmq.com/docs/install-rpm#red-hat-8-centos-stream-8-modern-fedora-releases -A 'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0' | grep -E 'https://github.com/rabbitmq/rabbitmq-server/releases/download/' | awk -F '["]' '{print $2}' | awk -F [/] '{print $9}')

if [[ "$os_base" == debian ]]
then
  apt-get install -qqy python3 python3-venv python3-pip python3-dev python3-setuptools libc6-dev rabbitmq-server gcc memcached
  (netstat -lnp | grep -q ':5672') || (echo -e "\033[0;101mERROR: start RabbitMQ server is failed\033[0m"; exit 1)
  apt-get install -qqy nwaf-mlc
elif [[ "$os_base" == ubuntu ]]
then
  if [[ "$os_code_name" == focal ]]
  then
    apt-get install -qqy python3.9 python3.9-venv python3-pip python3.9-dev python3-setuptools libc6-dev rabbitmq-server gcc memcached
  elif [[ "$os_code_name" =~ jammy|noble ]]
  then
    apt-get install -qqy python3 python3-venv python3-pip python3-dev python3-setuptools libc6-dev rabbitmq-server gcc memcached
  fi
  (netstat -lnp | grep -q ':5672') || (echo -e "\033[0;101mERROR: start RabbitMQ server is failed\033[0m"; exit 1)
  apt-get install -qqy nwaf-mlc
elif [[ "$os_base" =~ rhel|centos|rocky ]]
then
  dnf install -qqy epel-release
  dnf update -qqy
  rpm --import -qqy $rabbitmq_asc_url
  dnf install -qqy socat logrotate
  curl -O $rabbitmq_rpm_url
  dnf install -qqy $rabbitmq_rpm_name
  systemctl reenable rabbitmq-server
  systemctl restart rabbitmq-server
  (netstat -lnp | grep -q ':5672') || (echo -e "\033[0;101mERROR: start RabbitMQ server is failed\033[0m"; exit 1)
  if [[ "$os_version" == 8 ]]
  then
    dnf update -qqy
    dnf install -qqy epel-release
    dnf config-manager --set-enabled powertools
    dnf install -qqy python39 python39-devel python39-setuptools python39-pip gcc memcached
  elif [[ "$os_version" == 9 ]]
  then
    dnf update -qqy
    dnf install -qqy epel-release
    dnf config-manager --set-enabled crb
    dnf install -qqy python3 python3-devel python3-setuptools python3-pip gcc memcached
  fi
  dnf install -qqy nwaf-mlc
fi

## Configure Nemesida AI MLC settings file
sed -i "s|nwaf_license_key = |nwaf_license_key = $nwaf_lic_key|" /opt/mlc/mlc.conf
sed -i "s|sys_proxy = |sys_proxy = $sys_proxy|" /opt/mlc/mlc.conf
sed -i "s|api_proxy = |api_proxy = $api_proxy|" /opt/mlc/mlc.conf
sed -r "s|localhost|$api_srv_ip|" /opt/mlc/mlc.conf
sed -r "s|rmq_host = guest:guest@127.0.0.1|rmq_host = $dyn_rmq_user:$dyn_rmq_pwd@$dyn_srv_ip|" /opt/mlc/mlc.conf

## Start Nemesida AI MLC service
systemctl restart mlc_main rabbitmq-server memcached
