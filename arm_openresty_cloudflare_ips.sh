#!/bin/bash

# Cloudflare IP sources
IPV4_URL="https://www.cloudflare.com/ips-v4"
IPV6_URL="https://www.cloudflare.com/ips-v6"

# Target output file
OUTPUT_FILE="/usr/local/openresty/nginx/cloudflare_ips.conf"

# Fetch Cloudflare IPs and generate configuration file
{
    echo "# Cloudflare IPv4"
    curl -s $IPV4_URL | awk '{print "set_real_ip_from " $1 ";"}'

    echo "# Cloudflare IPv6"
    curl -s $IPV6_URL | awk '{print "set_real_ip_from " $1 ";"}'

    # Add configuration for real client IP header
    echo "real_ip_header CF-Connecting-IP;"
} > $OUTPUT_FILE

# Set appropriate permissions for the file
chmod 644 $OUTPUT_FILE

# Test and reload Nginx configuration
nginx -t && systemctl reload nginx

# Add to crontab for automatic updates
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/cloudflare_ips.sh") | crontab -
