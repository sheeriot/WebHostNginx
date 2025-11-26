#!/bin/sh
set -e

echo "===== Certificate Management Starting ====="
export HOME="/root"

# Source web.sites configuration
if [ -f "/root/resources/web.sites" ]; then
    . /root/resources/web.sites
else
    echo "ERROR: web.sites configuration file not found"
    exit 1
fi

# Initialize
CERTBOT_TEST=${CERTBOT_TEST:-false}
DOMAINS=""

# Process applications
if [ -n "$APPS" ]; then
    IFS=","
    for app in ${APPS}; do
        APPNAME=$(echo "$app" | tr '[:lower:]' '[:upper:]')
        APP_DNSVAR="${APPNAME}_DNS"
        eval APP_DNS=\$$APP_DNSVAR
        
        if [ -n "$APP_DNS" ]; then
            DOMAINS="${DOMAINS}${APP_DNS},"
        fi
    done
fi

# Process static sites
if [ -n "$STATIC_SITES" ]; then
    IFS=","
    for site in ${STATIC_SITES}; do
        SITE_NAME=$(echo "$site" | tr '[:lower:]' '[:upper:]')
        SITE_DNSVAR="${SITE_NAME}_DNS"
        eval SITE_DNS=\$$SITE_DNSVAR
        
        if [ -n "$SITE_DNS" ]; then
            DOMAINS="${DOMAINS}${SITE_DNS},"
        fi
    done
fi

# Validate domains
if [ -z "$DOMAINS" ]; then
    echo "ERROR: No domains configured"
    exit 1
fi

# Remove trailing comma
DOMAINS="${DOMAINS%,}"
echo "Managing SSL certificates for domains: ${DOMAINS}"

# Run certbot
echo "Running certbot with webroot authenticator..."
if [ "${CERTBOT_TEST}" = true ]; then
    echo "Certbot Dry-Run"
    certbot certonly \
        --webroot -w /var/www/certbot \
        --email "${CERTBOT_EMAIL}" \
        -d "${DOMAINS}" \
        --agree-tos \
        --non-interactive \
        --rsa-key-size 4096 \
        --dry-run \
        --expand || exit 5
else
    echo "Certbot Do-It"
    certbot certonly \
        --webroot -w /var/www/certbot \
        --email "${CERTBOT_EMAIL}" \
        -d "${DOMAINS}" \
        --agree-tos \
        --non-interactive \
        --rsa-key-size 4096 \
        --expand || exit 5
    
    # Reload NGINX if it is running to pick up new certs
    if pgrep nginx > /dev/null; then
        echo "Reloading NGINX to apply new certificates..."
        nginx -s reload
    fi
fi

echo "===== Certificate Management Complete ====="
