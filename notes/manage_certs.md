docker compose exec nginx /usr/local/bin/manage_certs.sh

docker compose exec nginx nginx -s reload