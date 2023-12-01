# entrypoint script for nginx container

export HOME="/root"
cd $HOME || exit 2

# check needed .env settings
if [ -z "$CERTBOT_DOMAINS" ] || [ "$CERTBOT_DOMAINS" = "." ]; then
	echo "The docker-compose script must set CERTBOT_DOMAINS to value to be passed to certbot for --domains" 
	exit 3
fi

if [ -z "$CERTBOT_EMAIL" ] || [ "$CERTBOT_EMAIL" = "." ]; then
	echo "The docker-compose script must set CERTBOT_EMAIL to an email address useful to certbot/letsencrypt for notifications"
	exit 3
fi

if [ -z "$NGINX_FQDN" ] || [ "$NGINX_FQDN" = "." ]; then
	echo "The docker-compose script must set NGINX_FQDN to the (single) fully-qualified domain at the top level"
	exit 3
fi

# copy the file apps to /etc/nginx/conf.d
sed -e "s/@{FQDN}/${NGINX_FQDN}/g" /root/resources/nginx_app80.conf > /etc/nginx/conf.d/app80.conf || exit 4
sed -e "s/@{FQDN}/${NGINX_FQDN}/g" /root/resources/nginx_app443.conf > /etc/nginx/conf.d/app443.conf || exit 5
