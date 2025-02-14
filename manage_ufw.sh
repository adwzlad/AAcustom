#!/bin/bash

CONFIG_FILE="/etc/nginx/cloudflare_ips.conf"
UFW_SCRIPT="/usr/local/bin/update_ufw_rules.sh"

# 检测 UFW 是否安装，未安装则自动安装
check_and_install_ufw() {
    if ! command -v ufw &> /dev/null; then
        echo "UFW 未安装，正在安装..."
        sudo apt update
        sudo apt install -y ufw
        echo "UFW 安装完成"
    fi
}

# 直接从 cloudflare_ips.conf 提取 IP 更新 UFW，避免重复下载
update_cloudflare_ips() {
    if [ -f "$CONFIG_FILE" ]; then
        echo "从 cloudflare_ips.conf 加载 Cloudflare IP..."
        IP_LIST=$(grep -oP '(?<=set_real_ip_from )[\d./:]+' "$CONFIG_FILE")
    else
        echo "cloudflare_ips.conf 未找到，直接从 Cloudflare 获取最新 IP..."
        CLOUDFLARE_IPV4="https://www.cloudflare.com/ips-v4"
        CLOUDFLARE_IPV6="https://www.cloudflare.com/ips-v6"
        IP_LIST=$(curl -s $CLOUDFLARE_IPV4; curl -s $CLOUDFLARE_IPV6)
    fi

    echo "清除旧 Cloudflare 规则..."
    sudo ufw status numbered | grep "ALLOW IN" | awk '{print $3}' | while read -r ip; do
        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || $ip =~ ^[0-9a-fA-F:]+$ ]]; then
            sudo ufw delete allow from "$ip" > /dev/null 2>&1
        fi
    done

    echo "添加最新 Cloudflare 规则..."
    for ip in $IP_LIST; do
        sudo ufw allow from "$ip" to any port 80,443 proto tcp
    done

    echo "Cloudflare 规则已更新！"
    sudo ufw reload
}

# 配置 SSH 端口保护
setup_ssh_security() {
    echo "1) 设置 SSH 端口"
    echo "2) 启用 Fail2Ban 保护 SSH"
    read -p "请选择: " choice
    case $choice in
        1)
            read -p "请输入新的 SSH 端口: " ssh_port
            sudo ufw allow "$ssh_port"/tcp
            echo "SSH 端口已开放：$ssh_port"
            sudo ufw reload
            ;;
        2)
            if ! command -v fail2ban-client &> /dev/null; then
                echo "Fail2Ban 未安装，正在安装..."
                sudo apt update && sudo apt install -y fail2ban
                sudo systemctl enable --now fail2ban
            fi
            read -p "最大失败次数 (默认: 3): " maxretry
            read -p "封禁时间 (秒, 默认: 1200): " bantime
            maxretry=${maxretry:-3}
            bantime=${bantime:-1200}
            sudo bash -c "cat > /etc/fail2ban/jail.local" <<EOL
[sshd]
enabled = true
maxretry = $maxretry
bantime = $bantime
EOL
            sudo systemctl restart fail2ban
            echo "Fail2Ban 已启用 (maxretry: $maxretry, bantime: $bantime 秒)"
            ;;
        *) echo "无效选项！" ;;
    esac
}

# 只允许 Cloudflare IP 访问 80/443
block_direct_access() {
    echo "阻止非 Cloudflare 访问..."
    sudo ufw default deny incoming
    sudo ufw allow ssh
    update_cloudflare_ips
    echo "已阻止所有非 Cloudflare HTTP 访问，并确保 SSH 可用"
}

# 立即更新 Cloudflare 规则并提示设置定时更新
immediately_update_cloudflare_ips() {
    update_cloudflare_ips
    setup_cron_job_prompt
}

# 提示是否要设置定时更新任务
setup_cron_job_prompt() {
    read -p "是否设置 Cloudflare IP 定时更新任务？(y/n): " answer
    case $answer in
        [Yy]*)
            read -p "请输入定时更新时间（格式：分钟 小时，例如 0 4 表示凌晨 4 点）: " cron_time
            setup_cron_job "$cron_time"
            ;;
        *) echo "未设置定时任务。" ;;
    esac
}

# 定时更新 Cloudflare IP 规则
setup_cron_job() {
    cron_time="$1"
    cron_job="$cron_time root $UFW_SCRIPT"
    echo "#!/bin/bash" > "$UFW_SCRIPT"
    echo "update_cloudflare_ips" >> "$UFW_SCRIPT"
    chmod +x "$UFW_SCRIPT"

    crontab -l 2>/dev/null | grep -v "$UFW_SCRIPT" | crontab -
    if ! crontab -l 2>/dev/null | grep -q "$UFW_SCRIPT"; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        echo "已添加 Cloudflare IP 定期更新任务，每天 $cron_time 执行一次"
    else
        echo "定时任务已存在"
    fi
}

# 启动或重启 UFW
start_or_restart_ufw() {
    read -p "选择操作 (1: 启动 UFW, 2: 重启 UFW): " action
    case $action in
        1) sudo ufw enable; echo "UFW 已启动" ;;
        2) sudo ufw reload; echo "UFW 已重启" ;;
        *) echo "无效选项！" ;;
    esac
}

# 主菜单
while true; do
    echo "======================="
    echo " UFW 防火墙管理菜单 "
    echo "======================="
    echo "1. 配置 SSH 安全性"
    echo "2. 屏蔽服务器真实 IP 直接访问（仅允许 Cloudflare & SSH）"
    echo "3. 允许 Cloudflare 访问 80/443"
    echo "4. 立即更新 Cloudflare 规则"
    echo "5. 启动或重启 UFW 使规则生效"
    echo "6. 退出"
    read -p "请输入选项: " option
    case $option in
        1) setup_ssh_security ;;
        2) block_direct_access ;;
        3) immediately_update_cloudflare_ips ;;
        4) update_cloudflare_ips ;;
        5) start_or_restart_ufw ;;
        6) echo "退出，重启 UFW 以确保规则生效..."; sudo ufw reload; exit 0 ;;
        *) echo "无效选项！" ;;
    esac
done
