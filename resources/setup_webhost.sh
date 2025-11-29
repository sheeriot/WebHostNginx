#!/bin/sh
set -e

echo "===== Webhost Setup Starting ====="
export HOME="/root"

# Validate required files
[ -f "/root/resources/web.sites" ] || { echo "ERROR: web.sites not found"; exit 1; }
[ -d "/etc/nginx/conf.d" ] || { echo "ERROR: nginx conf.d not found"; exit 1; }

# Source configuration
. /root/resources/web.sites

# Check for existing certificates
echo "Checking for existing certificates..."

# Identify the Primary Certificate Domain (first domain in APPS or STATIC_SITES)
PRIMARY_DOMAIN=""
if [ -n "$APPS" ]; then
    PRIMARY_DOMAIN=$(echo "$APPS" | cut -d',' -f1 | tr '[:lower:]' '[:upper:]')
    DNS_VAR="${PRIMARY_DOMAIN}_DNS"
    eval PRIMARY_DOMAIN=\$$DNS_VAR
elif [ -n "$STATIC_SITES" ]; then
    PRIMARY_DOMAIN=$(echo "$STATIC_SITES" | cut -d',' -f1 | tr '[:lower:]' '[:upper:]')
    DNS_VAR="${PRIMARY_DOMAIN}_DNS"
    eval PRIMARY_DOMAIN=\$$DNS_VAR
fi

CERT_PATH="/etc/letsencrypt/live/${PRIMARY_DOMAIN}/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/${PRIMARY_DOMAIN}/privkey.pem"

MISSING_CERTS=false
if [ -z "$PRIMARY_DOMAIN" ]; then
    echo "ERROR: Could not determine primary domain."
    exit 1
fi

if [ ! -f "$CERT_PATH" ]; then
    echo "Missing primary certificate for ${PRIMARY_DOMAIN}"
    MISSING_CERTS=true
else
    echo "Found primary certificate at ${CERT_PATH}"
fi

# Function to generate NGINX configs
generate_configs() {
    local MODE=$1 # "bootstrap" or "production"
    echo "Generating NGINX configurations in ${MODE} mode..."

    # Process APPS
    if [ -n "$APPS" ]; then
        IFS=","
        for app in ${APPS}; do
            APPNAME=$(echo "$app" | tr '[:lower:]' '[:upper:]')
            APP_DNSVAR="${APPNAME}_DNS"
            APP_PORTVAR="${APPNAME}_PORT"
            APP_UPSTREAMVAR="${APPNAME}_UPSTREAM"
            
            eval APP_DNS=\$$APP_DNSVAR
            eval APP_PORT=\$$APP_PORTVAR
            eval APP_UPSTREAM=\$$APP_UPSTREAMVAR
            if [ -z "$APP_UPSTREAM" ]; then APP_UPSTREAM=$app; fi

            if [ -f "/root/resources/nginx_${app}.conf" ]; then
                TEMPLATE="/root/resources/nginx_${app}.conf"
            else
                TEMPLATE="/root/resources/nginx_app.conf"
            fi

            TARGET="/etc/nginx/conf.d/${app}.conf"
            
            # Copy template to target first
            cp "$TEMPLATE" "$TARGET"

            # Apply variable substitutions
            sed -i "s/@{FQDN}/${APP_DNS}/g" "$TARGET"
            sed -i "s/@{APPNAME}/${app}/g" "$TARGET"
            sed -i "s/@{PORT}/${APP_PORT}/g" "$TARGET"
            sed -i "s/@{UPSTREAM_HOST}/${APP_UPSTREAM}/g" "$TARGET"
            
            # Update SSL certificate paths to point to the primary certificate
            # We use | delimiter to avoid conflicts with / in paths
            sed -i "s|/etc/letsencrypt/live/@{FQDN}/fullchain.pem|${CERT_PATH}|g" "$TARGET"
            sed -i "s|/etc/letsencrypt/live/${APP_DNS}/fullchain.pem|${CERT_PATH}|g" "$TARGET"
            sed -i "s|/etc/letsencrypt/live/@{FQDN}/privkey.pem|${KEY_PATH}|g" "$TARGET"
            sed -i "s|/etc/letsencrypt/live/${APP_DNS}/privkey.pem|${KEY_PATH}|g" "$TARGET"

            # If in bootstrap mode (no certs), remove HTTPS block entirely and disable redirect
            if [ "$MODE" = "bootstrap" ]; then
                # Delete everything from "# HTTPS Server Block" to end of file
                sed -i '/# HTTPS Server Block/,$d' "$TARGET"
                
                # Remove the redirect line (needed for certbot verification in bootstrap)
                sed -i '/return 301/d' "$TARGET"
            fi
        done
    fi

    # Process STATIC SITES
    if [ -n "$STATIC_SITES" ]; then
        IFS=","
        for site in ${STATIC_SITES}; do
            SITE_NAME=$(echo "$site" | tr '[:lower:]' '[:upper:]')
            SITE_DNSVAR="${SITE_NAME}_DNS"
            SITE_DIRVAR="${SITE_NAME}_DIR"
            
            eval SITE_DNS=\$$SITE_DNSVAR
            eval SITE_DIR=\$$SITE_DIRVAR

            TEMPLATE="/root/resources/nginx_static.conf"
            TARGET="/etc/nginx/conf.d/${site}.conf"

            cp "$TEMPLATE" "$TARGET"
            sed -i "s/@{FQDN}/${SITE_DNS}/g" "$TARGET"
            sed -i "s#@{SITEPATH}#${SITE_DIR}#g" "$TARGET"

            # Update SSL certificate paths to point to the primary certificate
            sed -i "s|/etc/letsencrypt/live/@{FQDN}/fullchain.pem|${CERT_PATH}|g" "$TARGET"
            sed -i "s|/etc/letsencrypt/live/${SITE_DNS}/fullchain.pem|${CERT_PATH}|g" "$TARGET"
            sed -i "s|/etc/letsencrypt/live/@{FQDN}/privkey.pem|${KEY_PATH}|g" "$TARGET"
            sed -i "s|/etc/letsencrypt/live/${SITE_DNS}/privkey.pem|${KEY_PATH}|g" "$TARGET"

            if [ "$MODE" = "bootstrap" ]; then
                # Delete HTTPS block
                sed -i '/# HTTPS Server Block/,$d' "$TARGET"
                # Remove redirect
                sed -i '/return 301/d' "$TARGET"
            fi
        done
    fi
}

# Main Logic
if [ "$MISSING_CERTS" = "true" ]; then
    echo "Certificates missing. Entering BOOTSTRAP mode."
    
    # 1. Generate HTTP-only configs
    generate_configs "bootstrap"
    
    # 2. Start NGINX in background
    echo "Starting temporary NGINX..."
    echo "$(date) [info] Starting Webhost Setup (Bootstrap Mode)..." >> /var/log/nginx/security_violations.log
    nginx
    sleep 2 # Give it a moment to start
    
    # 3. Run Certbot
    echo "Running Certbot..."
    /usr/local/bin/manage_certs.sh
    
    # 4. Stop NGINX
    echo "Stopping temporary NGINX..."
    nginx -s stop
    sleep 2
    
    # 5. Check if we have certs now
    echo "Verifying certificates after Certbot..."
    if [ ! -f "$CERT_PATH" ]; then
        echo "Still missing primary certificate for ${PRIMARY_DOMAIN}"
        STILL_MISSING_CERTS=true
    else
        echo "Found primary certificate at ${CERT_PATH}"
        STILL_MISSING_CERTS=false
    fi

    if [ "$STILL_MISSING_CERTS" = "true" ]; then
        echo "WARNING: Certificates are still missing."
        echo "This is expected if CERTBOT_TEST=true (Dry Run) or if Certbot failed."
        echo "Keeping NGINX in BOOTSTRAP (HTTP-only) mode to ensure availability."
        # We do NOT switch to production configs here.
        # We need to make sure the bootstrap configs are persistent or re-generated if needed,
        # but they were generated in step 1 and we haven't overwritten them yet.
        # However, we just stopped nginx. The container entrypoint usually execs nginx.
        # We are currently IN the entrypoint script (setup_webhost.sh is called by docker-entrypoint.d).
        # When this script finishes, the main nginx process starts.
        # So leaving the configs as-is is correct.
    else
        # 6. Regenerate Full Configs
        echo "Certificates obtained. Generating PRODUCTION configs."
        generate_configs "production"
    fi
else
    echo "Certificates found. Generating PRODUCTION configs."
    generate_configs "production"
fi

echo "===== Webhost Setup Complete ====="
echo "$(date) [info] Webhost Setup Complete. Nginx is ready." >> /var/log/nginx/security_violations.log
