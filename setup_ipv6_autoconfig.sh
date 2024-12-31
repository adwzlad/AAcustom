#!/bin/bash

# 创建服务和脚本的批处理脚本

# 获取当前活动的网络接口
NET_INTERFACE=$(ip -6 route | grep default | awk '{print $5}' | head -n 1)
if [[ -z "$NET_INTERFACE" ]]; then
    echo "未找到活动的网络接口，确保系统已正确连接到网络。"
    exit 1
fi

# 创建脚本文件
SCRIPT_PATH="/usr/local/bin/ipv6_check_and_request.sh"
cat << 'EOF' > "$SCRIPT_PATH"
#!/bin/bash

# 自动获取网卡名称
NET_INTERFACE=$(ip -6 route | grep default | awk '{print $5}' | head -n 1)
if [[ -z "$NET_INTERFACE" ]]; then
    echo "未找到活动的网络接口。"
    exit 1
fi

# 检查是否已有 IPv6 公网地址
if ! ip -6 addr show "$NET_INTERFACE" | grep -q "global"; then
    echo "没有发现 IPv6 公网地址，尝试重新获取..."
    dhclient -6 "$NET_INTERFACE"
    if ip -6 addr show "$NET_INTERFACE" | grep -q "global"; then
        echo "成功获取到 IPv6 公网地址。"
    else
        echo "获取 IPv6 公网地址失败。"
    fi
else
    echo "已存在 IPv6 公网地址，无需重新获取。"
fi
EOF

# 确保脚本可执行
chmod +x "$SCRIPT_PATH"

# 创建 systemd 服务文件
SERVICE_PATH="/etc/systemd/system/ipv6-autoconfig.service"
cat << EOF > "$SERVICE_PATH"
[Unit]
Description=自动获取 IPv6 公网地址
After=network.target

[Service]
ExecStart=$SCRIPT_PATH
Type=oneshot

[Install]
WantedBy=multi-user.target
EOF

# 创建定时器文件
TIMER_PATH="/etc/systemd/system/ipv6-autoconfig.timer"
cat << EOF > "$TIMER_PATH"
[Unit]
Description=每隔 5 分钟检查 IPv6 地址并获取

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

# 重新加载 systemd
systemctl daemon-reload

# 启用并启动服务和定时器
systemctl enable ipv6-autoconfig.service
systemctl enable ipv6-autoconfig.timer
systemctl start ipv6-autoconfig.service
systemctl start ipv6-autoconfig.timer

echo "配置完成。服务已启用并运行。"
