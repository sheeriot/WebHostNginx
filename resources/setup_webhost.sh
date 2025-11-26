#!/bin/sh
set -e  # Exit immediately if a command exits with non-zero status

echo "===== Webhost Setup Starting ====="
export HOME="/root"

# Validate required files and directories
[ -f "/root/resources/web.sites" ] || { echo "ERROR: web.sites configuration file not found"; exit 1; }
[ -d "/etc/nginx/conf.d" ] || { echo "ERROR: nginx conf.d directory not found"; exit 1; }

# Source web.sites configuration
. /root/resources/web.sites

# Validate core requirements
[ -n "$CERTBOT_EMAIL" ] || { echo "ERROR: CERTBOT_EMAIL must be set in environment"; exit 1; }
[ -n "$APPS" ] || [ -n "$STATIC_SITES" ] || { echo "ERROR: No apps or static sites configured"; exit 1; }

# Initialize
CERTBOT_TEST=${CERTBOT_TEST:-false}
DOMAINS=""
echo "$(date): Starting webhost setup"

# Process applications
if [ -n "$APPS" ]; then
    echo "Processing applications..."
    IFS=","
    for app in ${APPS}; do
        echo "Configuring ${app}..."
        APPNAME=$(echo "$app" | tr '[:lower:]' '[:upper:]')
        APP_DNSVAR="${APPNAME}_DNS"
        APP_PORTVAR="${APPNAME}_PORT"
        eval APP_DNS=\$$APP_DNSVAR
        eval APP_PORT=\$$APP_PORTVAR

        # Check for an explicit upstream host, otherwise default to the app name
        APP_UPSTREAMVAR="${APPNAME}_UPSTREAM"
        eval APP_UPSTREAM=\$$APP_UPSTREAMVAR
        if [ -z "$APP_UPSTREAM" ]; then
            APP_UPSTREAM=$app
        fi

        echo "--> Processing app: '${app}'"
        echo "    DNS: ${APP_DNS}"
        echo "    Port: ${APP_PORT}"
        echo "    Upstream Host: ${APP_UPSTREAM}"

        # Validate app configuration
        [ -n "$APP_DNS" ] || { echo "ERROR: ${app} missing DNS configuration"; exit 1; }
        [ -n "$APP_PORT" ] || { echo "ERROR: ${app} missing PORT configuration"; exit 1; }

        # Check if app hostname is resolvable
        if ! getent hosts "${APP_DNS}" >/dev/null; then
            echo "WARNING: Hostname ${APP_DNS} for app ${app} is not resolvable. Skipping configuration."
            continue
        fi

        # Use app-specific config if it exists, otherwise use default
        if [ -f "/root/resources/nginx_${app}.conf" ]; then
            CONFIG_TEMPLATE="/root/resources/nginx_${app}.conf"
        else
            CONFIG_TEMPLATE="/root/resources/nginx_app.conf"
        fi
        [ -f "$CONFIG_TEMPLATE" ] || { echo "ERROR: nginx template not found: ${CONFIG_TEMPLATE}"; exit 1; }

        # Generate config
        sed -e "s/@{FQDN}/${APP_DNS}/g" \
            -e "s/@{APPNAME}/${app}/g" \
            -e "s/@{PORT}/${APP_PORT}/g" \
            -e "s/@{UPSTREAM_HOST}/${APP_UPSTREAM}/g" \
            "$CONFIG_TEMPLATE" > "/etc/nginx/conf.d/${app}.conf"

        DOMAINS="${DOMAINS}${APP_DNS},"
        echo "Successfully configured ${app}"
    done
fi

# Process static sites
if [ -n "$STATIC_SITES" ]; then
    echo "Processing static sites..."
    IFS=","
    for site in ${STATIC_SITES}; do
        echo "Configuring ${site}..."
        SITE_NAME=$(echo "$site" | tr '[:lower:]' '[:upper:]')
        SITE_DNSVAR="${SITE_NAME}_DNS"
        SITE_DIRVAR="${SITE_NAME}_DIR"
        eval SITE_DNS=\$$SITE_DNSVAR
        eval SITE_DIR=\$$SITE_DIRVAR

        # Validate static site configuration
        [ -n "$SITE_DNS" ] || { echo "ERROR: ${site} missing DNS configuration"; exit 1; }
        [ -n "$SITE_DIR" ] || { echo "ERROR: ${site} missing DIR configuration for ${site}"; exit 1; }
        [ -d "$SITE_DIR" ] || { echo "ERROR: Directory ${SITE_DIR} not found for site ${site}"; exit 1; }
        [ -f "/root/resources/nginx_static.conf" ] || { echo "ERROR: nginx static template not found"; exit 1; }

        # Generate config
        sed -e "s/@{FQDN}/${SITE_DNS}/g" \
            -e "s#@{SITEPATH}#${SITE_DIR}#g" \
            "/root/resources/nginx_static.conf" > "/etc/nginx/conf.d/${site}.conf"

        DOMAINS="${DOMAINS}${SITE_DNS},"
        echo "Successfully configured static site ${site}"
    done
fi

# Prepare domains for certbot
[ -n "$DOMAINS" ] || { echo "ERROR: No domains configured"; exit 1; }
# Remove trailing comma
DOMAINS="${DOMAINS%,}"
echo "Configuring SSL certificates for domains: ${DOMAINS}"

# Run certbot
if [ "${CERTBOT_TEST}" = true ]; then
    echo "Certbot Dry-Run"
    certbot certonly --dry-run --agree-tos --email "${CERTBOT_EMAIL}" -d "${DOMAINS}" --non-interactive --nginx --rsa-key-size 4096 --expand|| exit 5
    # Stop nginx (started by certbot)
    /usr/sbin/nginx -s stop && echo "stopped successfully"
else
    echo "Certbot Do-It"
    certbot --agree-tos --email "${CERTBOT_EMAIL}" -d "${DOMAINS}" --non-interactive --nginx --rsa-key-size 4096 --expand || exit 5
    # Stop nginx (started by certbot)
    /usr/sbin/nginx -s stop && echo "NGINX Stopped after Certbot Issued Cert successfully"
fi

echo "===== Webhost Setup Complete ====="
