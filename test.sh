#!/bin/bash

CLOUDFLARE_IPV4="https://www.cloudflare.com/ips-v4"
CLOUDFLARE_IPV6="https://www.cloudflare.com/ips-v6"
CLOUDFLARE_CACHE="/tmp/cloudflare_ips"
UFW_RULES_FILE="/etc/ufw/user.rules"
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

# 缓存 Cloudflare IP
update_cloudflare_cache() {
    echo "更新 Cloudflare IP 缓存..."
    curl -s "$CLOUDFLARE_IPV4" > "$CLOUDFLARE_CACHE-v4"
    curl -s "$CLOUDFLARE_IPV6" > "$CLOUDFLARE_CACHE-v6"
}

# 允许 Cloudflare 访问 80/443，确保优先级
allow_cloudflare() {
    if [[ ! -f "$CLOUDFLARE_CACHE-v4" || ! -f "$CLOUDFLARE_CACHE-v6" ]]; then
        update_cloudflare_cache
    fi
    
    echo "正在添加 Cloudflare 访问规则..."
    for ip in $(cat "$CLOUDFLARE_CACHE-v4"); do
        if ! ufw_rule_exists "$ip 80"; then
            sudo ufw insert 1 allow from "$ip" to any port 80
        fi
        if ! ufw_rule_exists "$ip 443"; then
            sudo ufw insert 1 allow from "$ip" to any port 443
        fi
    done
    for ip in $(cat "$CLOUDFLARE_CACHE-v6"); do
        if ! ufw_rule_exists "$ip 80"; then
            sudo ufw insert 1 allow from "$ip" to any port 80
        fi
        if ! ufw_rule_exists "$ip 443"; then
            sudo ufw insert 1 allow from "$ip" to any port 443
        fi
    done
    echo "Cloudflare 规则添加完成，并确保优先级"
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
    sudo ufw allow "$ssh_port"/udp
}

# 设置 Fail2Ban 以防止 SSH 暴力破解
setup_fail2ban() {
    if ! command -v fail2ban-client &> /dev/null; then
        echo "Fail2Ban 未安装，正在安装..."
        sudo apt update && sudo apt install -y fail2ban
    fi
    
    if [[ ! -f "$FAIL2BAN_JAIL_FILE" ]]; then
        echo "创建 Fail2Ban 自定义配置..."
        sudo bash -c "cat > $FAIL2BAN_JAIL_FILE <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 1200
EOF"
    fi
    
    sudo systemctl enable fail2ban
    sudo systemctl restart fail2ban
    echo "Fail2Ban 已启用，SSH 失败登录保护已开启"
}

# 屏蔽直接访问服务器 IP
block_direct_access() {
    local interface=$(get_default_interface)
    sudo ufw deny in on "$interface"
    echo "已阻止所有对服务器真实 IP 的直接访问"
}

# 读取 UFW 规则，防止重复添加
ufw_rule_exists() {
    local rule="$1"
    sudo ufw status numbered | grep -q "$rule"
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

# 交互式菜单
while true; do
    echo "======================="
    echo " UFW 防火墙管理菜单 "
    echo "======================="
    echo "1. 配置 SSH 安全性"
    echo "2. 屏蔽服务器真实 IP 直接访问"
    echo "3. 允许 Cloudflare 访问 80/443"
    echo "4. 退出"
    read -p "请输入选项: " choice
    case "$choice" in
        1) configure_ssh_security ;;
        2) block_direct_access ;;
        3) allow_cloudflare ;;
        4) exit 0 ;;
        *) echo "无效选项，请重新输入。" ;;
    esac
done
