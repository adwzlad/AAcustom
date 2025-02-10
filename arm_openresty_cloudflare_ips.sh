#!/bin/bash

# Cloudflare IP sources
IPV4_URL="https://www.cloudflare.com/ips-v4"
IPV6_URL="https://www.cloudflare.com/ips-v6"

# Target output file
OUTPUT_FILE="/usr/local/openresty/nginx/cloudflare_ips.conf"

# Ensure OpenResty binary is in PATH (for cron jobs)
export PATH="/usr/local/openresty/nginx/sbin:$PATH"

# Fetch Cloudflare IPs and generate configuration file safely
{
    echo "# Cloudflare IPv4"
    if ! curl -s "$IPV4_URL"; then
        echo "Error: Failed to fetch IPv4 addresses." >&2
        exit 1
    fi | awk '{print "set_real_ip_from " $1 ";"}'

    echo "# Cloudflare IPv6"
    if ! curl -s "$IPV6_URL"; then
        echo "Error: Failed to fetch IPv6 addresses." >&2
        exit 1
    fi | awk '{print "set_real_ip_from " $1 ";"}'

    echo "real_ip_header CF-Connecting-IP;"
} > "$OUTPUT_FILE"

# Set appropriate permissions for the file
chmod 644 "$OUTPUT_FILE"

# Test and reload Nginx configuration safely
if openresty -t; then
    openresty -s reload
    echo "OpenResty configuration reloaded successfully."
else
    echo "Error: Nginx configuration test failed! Check your config before reloading." >&2
    exit 1
fi

# Add to crontab if not already present
if ! crontab -l 2>/dev/null | grep -q "/usr/local/bin/cloudflare_ips.sh"; then
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/cloudflare_ips.sh") | crontab -
    echo "Cron job added for automatic updates."
else
    echo "Cron job already exists."
fi
