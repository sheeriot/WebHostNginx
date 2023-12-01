FROM nginx:stable-alpine

COPY resources /root/resources/

RUN mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
#
# done in startup - needs ENV settings
RUN cp /root/resources/setup_webhost.sh /docker-entrypoint.d
RUN chmod +x /docker-entrypoint.d/setup_webhost.sh
