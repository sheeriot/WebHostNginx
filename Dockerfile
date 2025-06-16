FROM nginx:stable-alpine

RUN apk add certbot certbot-nginx

COPY resources /root/resources/

# rid the original nginx config
RUN mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
RUN cp /root/resources/nginx.conf /etc/nginx/conf.d

# give it a startup script to setup nginx
RUN cp /root/resources/setup_webhost.sh /docker-entrypoint.d
RUN chmod +x /docker-entrypoint.d/setup_webhost.sh

RUN cp /root/resources/favicon.ico /usr/share/nginx/html

# Create required directories
RUN mkdir -p /var/www/sites \
    && mkdir -p /etc/letsencrypt \
    && mkdir -p /var/www/certbot
