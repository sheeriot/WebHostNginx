#!/bin/sh

echo "----- setup webhost -----"
export HOME="/root"

cd $HOME || exit 2

# check needed environment settings
if [ -z "$APPS" ]; then
	echo "The container must have an APPS variable set to a comma-separated list of application names" 
	exit 3
fi

if [ -z "$CERTBOT_EMAIL" ]; then
	echo "The container must have a CERTBOT_EMAIL variable set to an email address useful to certbot/letsencrypt for notifications"
	exit 3
fi

# more variable setup
CERTBOT_TEST=${CERTBOT_TEST:-false}
DOMAINS=""
IFS=","
for app in ${APPS}; do
    APPNAME=$(echo "$app" | tr '[:lower:]' '[:upper:]')
    APP_DNSVAR="${APPNAME}_DNS"
    eval APP_DNS=\$$APP_DNSVAR
    APP_PORTVAR="${APPNAME}_PORT"
    eval APP_PORT=\$$APP_PORTVAR

    sed -e "s/@{FQDN}/${APP_DNS}/g" /root/resources/nginx_app.conf > /etc/nginx/conf.d/${app}.conf || exit 4
    sed -i "s/@{APPNAME}/${app}/g" /etc/nginx/conf.d/${app}.conf || exit 4
    sed -i "s/@{PORT}/${APP_PORT}/g" /etc/nginx/conf.d/${app}.conf || exit 4
	
    DOMAINS="${DOMAINS}${APP_DNS},"
done

# Get DNS list for Certs
IFS=" "
DOMAINS="${DOMAINS%,}"

if [ "${CERTBOT_TEST}" = true ]; then
	# set for dry-run
	echo "Certbot Dry-Run"
	certbot certonly --dry-run --agree-tos --email "${CERTBOT_EMAIL}" -d ${DOMAINS} --non-interactive ${CERTBOT_DOMAINS} --nginx --rsa-key-size 4096 --redirect || exit 5

	# certbot actually launched Nginx. The simple hack is to stop it; then launch 
	# it again after we've edited the config files.
	/usr/sbin/nginx -s stop && echo "stopped successfully"
else
	echo "Certbot Do-It"
	certbot --agree-tos --email "${CERTBOT_EMAIL}" -d ${DOMAINS}  --non-interactive --nginx --rsa-key-size 4096 --redirect || exit 5
	# certbot actually launched Nginx. The simple hack is to stop it; then launch 
	# it again after we've edited the config files.
	/usr/sbin/nginx -s stop && echo "NGINX Stopped after Certbot Issued Cert successfully"
fi

# note that Cerbot modifies the config file as needed to install 443 config
