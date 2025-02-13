#!/bin/bash

# Cloudflare IP sources
IPV4_URL="https://www.cloudflare.com/ips-v4"
IPV6_URL="https://www.cloudflare.com/ips-v6"

# 配置文件路径
CONFIG_FILE="/etc/cloudflare_ips_config.txt"
NEW_SCRIPT="/usr/local/bin/cloudflare_ips_task.sh"

# 确保脚本以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 权限执行此脚本（sudo bash $0）"
    exit 1
fi

# 检查并创建配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    touch "$CONFIG_FILE"
    chmod 664 "$CONFIG_FILE"
    chown root:root "$CONFIG_FILE"
fi

# 读取旧配置
if [ -s "$CONFIG_FILE" ]; then
    OLD_OUTPUT_FILE=$(awk 'NR==1' "$CONFIG_FILE")
    OLD_CRON_TIME=$(awk 'NR==2' "$CONFIG_FILE")
fi

# 提示用户输入新参数
read -p "请输入 Cloudflare IP 配置保存路径（默认：${OLD_OUTPUT_FILE:-/etc/nginx/cloudflare_ips.conf}）: " OUTPUT_FILE
OUTPUT_FILE=${OUTPUT_FILE:-${OLD_OUTPUT_FILE:-/etc/nginx/cloudflare_ips.conf}}

read -p "请输入定时更新时间（分钟 小时，例如 0 2 表示凌晨 2 点，默认：${OLD_CRON_TIME:-'0 2'}）: " CRON_TIME
CRON_TIME=${CRON_TIME:-${OLD_CRON_TIME:-'0 2'}}

# 保存新配置
echo "$OUTPUT_FILE" > "$CONFIG_FILE"
echo "$CRON_TIME" >> "$CONFIG_FILE"

# 生成 Cloudflare IP 更新脚本
cat << EOF > "$NEW_SCRIPT"
#!/bin/bash

OUTPUT_FILE="$OUTPUT_FILE"

# 检查目录是否存在，不存在则创建
OUTPUT_DIR=\$(dirname "\$OUTPUT_FILE")
[ ! -d "\$OUTPUT_DIR" ] && mkdir -p "\$OUTPUT_DIR"

# 获取 Cloudflare IP 并写入配置
{
    echo "# Cloudflare IPv4"
    curl -s $IPV4_URL | awk '{print "set_real_ip_from " \$1 ";"}'
    echo "# Cloudflare IPv6"
    curl -s $IPV6_URL | awk '{print "set_real_ip_from " \$1 ";"}'
    echo "real_ip_header CF-Connecting-IP;"
} > "\$OUTPUT_FILE"

# 设置适当权限
chmod 644 "\$OUTPUT_FILE"

# 检查并重载 Nginx
if nginx -t; then
    systemctl reload nginx
    echo "Cloudflare IP 更新成功，并已重新加载 Nginx"
else
    echo "Nginx 配置检查失败，请检查 \$OUTPUT_FILE"
    systemctl status nginx --no-pager
    exit 1
fi
EOF

chmod +x "$NEW_SCRIPT"

# 立即执行一次
"$NEW_SCRIPT"

# 显示生成的配置文件内容
echo "cloudflare_ips.conf 文件内容如下："
cat "$OUTPUT_FILE"

# 配置 crontab 任务（清除旧的，再添加新的）
(sudo crontab -l 2>/dev/null | grep -v "$NEW_SCRIPT"; echo "$CRON_TIME $NEW_SCRIPT") | sudo crontab -

echo "已添加 Cloudflare IP 定期更新任务，每天 $CRON_TIME 执行一次"
