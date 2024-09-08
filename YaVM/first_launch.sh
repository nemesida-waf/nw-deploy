#!/bin/bash

script_name="$(dirname $0)/$(basename $0)"
conf_file_cab='/var/www/app/cabinet/settings.py'
conf_file_api='/var/www/nw-api/settings.py'
secret_key=$(echo $RANDOM | md5sum | sha256sum | awk '{print $1}')
db_pwd_cab=$(echo $RANDOM | md5sum | head -c 10)
db_pwd_api=$(echo $RANDOM | md5sum | head -c 10)

sed -i -r "s/SECRET_KEY\s*=.+/SECRET_KEY = '$secret_key'/" $conf_file_cab
sed -i -r "s/DB_PASS_CABINET\s*=.+/DB_PASS_CABINET = '$db_pwd_cab'/" $conf_file_cab
sed -i -r "s/DB_PASS_CONF\s*=.+/DB_PASS_CONF = '$db_pwd_api'/" $conf_file_cab
sed -i -r "s/DB_PASS\s*=.+/DB_PASS = '$db_pwd_api'/" $conf_file_api

echo "ALTER USER nw_cabinet PASSWORD '$db_pwd_cab';" | su - postgres -c "psql -q"
echo "ALTER USER nw_api PASSWORD '$db_pwd_api';" | su - postgres -c "psql -q"

systemctl restart nw-api cabinet
cd /var/www/app/ && . venv/bin/activate && python3 manage.py migrate && python3 manage.py createsuperuser && deactivate
systemctl restart nw-api cabinet cabinet_ipinfo cabinet_attack_notification cabinet_cleaning_db

echo "Initialization of settings: DONE"
rm -f "$script_name"
