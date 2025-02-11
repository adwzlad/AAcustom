#!/bin/bash

CLOUDFLARE_IPV4="https://www.cloudflare.com/ips-v4"
CLOUDFLARE_IPV6="https://www.cloudflare.com/ips-v6"
CLOUDFLARE_CACHE="/tmp/cloudflare_ips"
SSH_CONFIG_FILE="/etc/ssh/sshd_config"
FAIL2BAN_JAIL_FILE="/etc/fail2ban/jail.local"

# 获取默认网卡
get_default_interface() {
    ip route | grep default | awk '{print $5}' | head -n 1
}

# 读取当前 SSH 端口
get_ssh_port() {
    grep -E "^Port " "$SSH_CONFIG_FILE" | awk '{print $2}'
}

# 更新 Cloudflare IP 缓存并刷新 UFW 规则
update_cloudflare_ips() {
    echo "更新 Cloudflare IP 缓存..."
    curl -s "$CLOUDFLARE_IPV4" > "$CLOUDFLARE_CACHE-v4"
    curl -s "$CLOUDFLARE_IPV6" > "$CLOUDFLARE_CACHE-v6"

    echo "清除旧 Cloudflare 规则..."
    sudo ufw status numbered | awk '/ALLOW IN/{print $2, $3}' | grep -E '80|443' | while read line; do
        sudo ufw delete allow from $line to any port 80,443
    done

    echo "添加最新 Cloudflare 规则..."
    for ip in $(cat "$CLOUDFLARE_CACHE-v4"); do
        sudo ufw allow from "$ip" to any port 80,443
    done
    for ip in $(cat "$CLOUDFLARE_CACHE-v6"); do
        sudo ufw allow from "$ip" to any port 80,443
    done

    echo "Cloudflare 规则已更新！"
}

# 配置 SSH 端口
configure_ssh_port() {
    local ssh_port=$(get_ssh_port)
    echo "当前 SSH 端口: $ssh_port"
    read -p "请输入新的 SSH 端口（留空保持默认）: " new_port
    if [[ -n "$new_port" ]]; then
        sudo sed -i "s/^Port .*/Port $new_port/" "$SSH_CONFIG_FILE"
        sudo systemctl restart sshd
        echo "SSH 端口已修改为 $new_port"
    fi
    sudo ufw allow "$ssh_port"/tcp
}

# 设置 Fail2Ban 以防止 SSH 暴力破解
setup_fail2ban() {
    read -p "请输入最大重试次数 (默认: 3): " maxretry
    read -p "请输入封禁时间 (秒，默认: 1200): " bantime

    maxretry=${maxretry:-3}
    bantime=${bantime:-1200}

    if ! command -v fail2ban-client &> /dev/null; then
        echo "Fail2Ban 未安装，正在安装..."
        sudo apt update && sudo apt install -y fail2ban
    fi

    echo "创建 Fail2Ban 配置..."
    sudo bash -c "cat > $FAIL2BAN_JAIL_FILE <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = $maxretry
bantime = $bantime
EOF"

    sudo systemctl enable fail2ban
    sudo systemctl restart fail2ban
    echo "Fail2Ban 已启用，SSH 失败登录保护已开启 (maxretry: $maxretry, bantime: $bantime 秒)"
}

# 屏蔽非 Cloudflare 访问并确保 SSH 连接
block_direct_access() {
    local interface=$(get_default_interface)
    local ssh_port=$(get_ssh_port)

    echo "设置 UFW 规则，确保 SSH 访问..."
    sudo ufw default deny incoming   # 默认拒绝所有入站流量
    sudo ufw allow "$ssh_port"/tcp   # 允许 SSH
    update_cloudflare_ips            # 仅允许 Cloudflare 访问 80/443

    echo "已阻止所有非 Cloudflare 的 HTTP 访问，并确保 SSH 可用"
}

# 配置 SSH 安全性
configure_ssh_security() {
    echo "1) 配置 SSH 端口"
    echo "2) 限制 SSH 登录失败次数 (Fail2Ban)"
    read -p "请选择: " sub_choice
    case "$sub_choice" in
        1) configure_ssh_port ;;
        2) setup_fail2ban ;;
        *) echo "无效选项" ;;
    esac
}

# 设置定期任务自动更新 Cloudflare IP
setup_cron() {
    local cron_job="0 */12 * * * /bin/bash -c '/path/to/this_script.sh --update-cloudflare'"

    # 检查是否已存在
    if crontab -l | grep -q "update-cloudflare"; then
        echo "定时任务已存在，无需添加"
    else
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        echo "已添加 Cloudflare IP 定期更新任务 (每 12 小时执行一次)"
    fi
}

# 交互式菜单
while true; do
    echo "======================="
    echo " UFW 防火墙管理菜单 "
    echo "======================="
    echo "1. 配置 SSH 安全性"
    echo "2. 屏蔽服务器真实 IP 直接访问（但允许 SSH 和 Cloudflare）"
    echo "3. 允许 Cloudflare 访问 80/443"
    echo "4. 立即更新 Cloudflare 规则"
    echo "5. 设置定时更新 Cloudflare IP（每 12 小时）"
    echo "6. 退出"
    read -p "请输入选项: " choice
    case "$choice" in
        1) configure_ssh_security ;;
        2) block_direct_access ;;
        3) update_cloudflare_ips ;;
        4) update_cloudflare_ips ;;
        5) setup_cron ;;
        6) exit 0 ;;
        *) echo "无效选项，请重新输入。" ;;
    esac
done
