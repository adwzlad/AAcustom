#!/bin/bash

# Cloudflare IP 资源地址
CLOUDFLARE_IPV4="https://www.cloudflare.com/ips-v4"
CLOUDFLARE_IPV6="https://www.cloudflare.com/ips-v6"

# 更新 Cloudflare IP 规则
update_cloudflare_ips() {
    echo "更新 Cloudflare IP 缓存..."
    local ips_v4=$(curl -s $CLOUDFLARE_IPV4)
    local ips_v6=$(curl -s $CLOUDFLARE_IPV6)
    
    echo "清除旧 Cloudflare 规则..."
    for ip in $ips_v4; do
        sudo ufw delete allow from "$ip" > /dev/null 2>&1
    done
    for ip in $ips_v6; do
        sudo ufw delete allow from "$ip" > /dev/null 2>&1
    done
    
    echo "添加最新 Cloudflare 规则..."
    for ip in $ips_v4; do
        sudo ufw allow from "$ip" to any port 80 proto tcp
        sudo ufw allow from "$ip" to any port 443 proto tcp
    done
    for ip in $ips_v6; do
        sudo ufw allow from "$ip" to any port 80 proto tcp
        sudo ufw allow from "$ip" to any port 443 proto tcp
    done
    echo "Cloudflare 规则已更新！"
}

# 设置 SSH 保护
setup_ssh_security() {
    echo "1) 配置 SSH 端口"
    echo "2) 限制 SSH 登录失败次数 (Fail2Ban)"
    read -p "请选择: " choice
    case $choice in
        1)
            read -p "请输入新的 SSH 端口: " ssh_port
            sudo ufw allow "$ssh_port"/tcp
            echo "SSH 端口已修改为 $ssh_port"
            ;;
        2)
            if ! command -v fail2ban-client &> /dev/null; then
                echo "Fail2Ban 未安装，正在安装..."
                sudo apt update && sudo apt install -y fail2ban
                sudo systemctl enable --now fail2ban
            fi
            read -p "请输入最大重试次数 (默认: 3): " maxretry
            read -p "请输入封禁时间 (秒，默认: 1200): " bantime
            maxretry=${maxretry:-3}
            bantime=${bantime:-1200}
            sudo bash -c "cat > /etc/fail2ban/jail.local" <<EOL
[sshd]
enabled = true
maxretry = $maxretry
bantime = $bantime
EOL
            sudo systemctl restart fail2ban
            echo "Fail2Ban 已启用，SSH 失败登录保护已开启 (maxretry: $maxretry, bantime: $bantime 秒)"
            ;;
        *) echo "无效选项！" ;;
    esac
}

# 屏蔽真实 IP 访问
block_direct_access() {
    echo "设置 UFW 规则，确保 SSH 访问..."
    sudo ufw default deny incoming
    sudo ufw allow ssh
    update_cloudflare_ips
    echo "已阻止所有非 Cloudflare 的 HTTP 访问，并确保 SSH 可用"
}

# 允许 Cloudflare 访问 80/443
allow_cloudflare_ports() {
    update_cloudflare_ips
}

# 定时更新 Cloudflare IP 规则
setup_cron_job() {
    (crontab -l 2>/dev/null | grep -v "update_cloudflare_ips"; echo "0 */12 * * * $(realpath $0) update_cloudflare_ips") | crontab -
    echo "已添加 Cloudflare IP 定期更新任务 (每 12 小时执行一次)"
}

# 主菜单
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
    read -p "请输入选项: " option
    case $option in
        1) setup_ssh_security ;;
        2) block_direct_access ;;
        3) allow_cloudflare_ports ;;
        4) update_cloudflare_ips ;;
        5) setup_cron_job ;;
        6) exit 0 ;;
        *) echo "无效选项！" ;;
    esac
done
