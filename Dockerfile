FROM nginx:stable-alpine

RUN apk add certbot certbot-nginx

COPY resources /root/resources/

# rid the original nginx config
RUN mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
RUN cp /root/resources/00-nginx-base.conf /etc/nginx/conf.d/00-nginx-base.conf

# give it a startup script to setup nginx
RUN cp /root/resources/setup_webhost.sh /docker-entrypoint.d
RUN cp /root/resources/manage_certs.sh /usr/local/bin/manage_certs.sh
RUN chmod +x /docker-entrypoint.d/setup_webhost.sh
RUN chmod +x /usr/local/bin/manage_certs.sh

RUN cp /root/resources/favicon.ico /usr/share/nginx/html

# Create required directories
RUN mkdir -p /var/www/sites \
    && mkdir -p /etc/letsencrypt \
    && mkdir -p /var/www/certbot
