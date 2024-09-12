#!/bin/bash

## OS detection
os_base=$(cat /etc/os-release | grep -E '^ID=' | awk '{print $2}' FS="=" | tr -d '"')
os_version=$(cat /etc/os-release | grep -E '^VERSION_ID=' | awk '{print $2}' FS="=" | tr -d '"' | grep -o '^[^.]*')
os_code_name=$(cat /etc/os-release | grep -E '^VERSION_CODENAME=' | awk '{print $2}' FS="=" | tr -d '"')

if ! [[ "$os_base" =~ debian|ubuntu|rhel|centos|rocky ]]
then
  echo -e "\033[0;101mUnsupported operating system. Please, contact us: info@nemesida-waf.com\033[0m"
  exit 1
fi

##
# Nemesida WAF repository
##

echo "Add Nemesida WAF repository"

if [[ "$os_base" == debian ]]
then
  apt-get install apt-transport-https gnupg2 curl -qqy
  echo "deb https://nemesida-security.com/repo/nw/debian $os_code_name non-free" > /etc/apt/sources.list.d/NemesidaWAF.list
  curl -s https://nemesida-security.com/repo/nw/gpg.key | gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/trusted.gpg --import
  chmod 644 /etc/apt/trusted.gpg.d/trusted.gpg
  apt-get update
fi

if [[ "$os_base" == ubuntu ]]
then
  apt-get install apt-transport-https gnupg2 curl -qqy
  echo "deb [arch=amd64] https://nemesida-security.com/repo/nw/ubuntu $os_code_name nwaf" > /etc/apt/sources.list.d/NemesidaWAF.list
  curl -s https://nemesida-security.com/repo/nw/gpg.key | gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/trusted.gpg --import
  chmod 644 /etc/apt/trusted.gpg.d/trusted.gpg
  apt-get update
fi

if [[ "$os_base" =~ centos|rhel|rocky ]]
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

echo "Setting up Nemesida WAF API"

if [[ "$os_base" == debian ]]
then
  apt-get install nginx python3-pip python3-dev postgresql-server-dev-all python3-venv memcached -qqy
  apt-get install nwaf-api -qqy
fi

if [[ "$os_base" == ubuntu ]]
then
  if [[ "$os_code_name" == focal ]]
  then
    apt-get install nginx python3.9 python3-pip python3.9-dev postgresql-server-dev-all python3.9-venv build-essential memcached -qqy
  elif [[ "$os_code_name" =~ jammy|noble ]]
  then
    apt-get install nginx python3 python3-pip python3-dev postgresql-server-dev-all python3-venv build-essential memcached -qqy
  fi
  apt-get install nwaf-api -qqy
fi

if [[ "$os_base" =~ centos|rhel|rocky ]]
then
  dnf install epel-release -qqy
  dnf update -qqy
  if [[ "$os_version" == 8 ]]
  then
    dnf install nginx python39 python39-devel python39-setuptools python39-pip postgresql-devel gcc memcached -qqy
  elif [[ "$os_version" == 9 ]]
  then
    dnf install nginx python3 python3-devel python3-setuptools python3-pip postgresql-devel gcc memcached -qqy
  fi
  dnf install nwaf-api -qqy
fi
