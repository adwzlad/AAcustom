#!/bin/bash

# 检查是否以 root 用户运行
if [[ $EUID -ne 0 ]]; then
    echo "请以 root 用户运行此脚本。"
    exit 1
fi

# 创建主脚本
cat << 'EOF' > /usr/local/bin/ipv6_checker.sh
#!/bin/bash

# 检测网卡名称
get_default_interface() {
    ip route | grep default | awk '{print $5}' | head -n 1
}

# 检测是否有公网 IPv6 地址
has_public_ipv6() {
    local interface=$1
    ip -6 addr show dev "$interface" scope global | grep -q "inet6"
    return $?
}

# 获取公网 IPv6 地址
get_ipv6() {
    local interface=$1
    dhclient -6 "$interface"
}

# 主逻辑
main() {
    local interface=$(get_default_interface)
    if [[ -z $interface ]]; then
        echo "未找到默认网卡，退出。"
        exit 1
    fi

    echo "检测网卡：$interface"

    if ! has_public_ipv6 "$interface"; then
        echo "未检测到公网 IPv6，尝试获取..."
        get_ipv6 "$interface"
        if has_public_ipv6 "$interface"; then
            echo "成功获取公网 IPv6。"
        else
            echo "获取公网 IPv6 失败。"
        fi
    else
        echo "公网 IPv6 已存在，无需操作。"
    fi
}

main
EOF

# 设置主脚本可执行权限
chmod +x /usr/local/bin/ipv6_checker.sh

# 创建服务文件
cat << 'EOF' > /etc/systemd/system/ipv6_checker.service
[Unit]
Description=IPv6 Checker Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ipv6_checker.sh

[Install]
WantedBy=multi-user.target
EOF

# 创建计时器文件
cat << 'EOF' > /etc/systemd/system/ipv6_checker.timer
[Unit]
Description=Run IPv6 Checker every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 重新加载 systemd 配置
systemctl daemon-reload

# 启用并启动服务和定时器
systemctl enable ipv6_checker.service
systemctl enable ipv6_checker.timer
systemctl start ipv6_checker.timer

echo "IPv6 检测和获取功能已成功配置！"
echo "系统将在开机时和每 5 分钟自动检查并获取公网 IPv6 地址。"
