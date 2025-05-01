#!/bin/bash

# 设置变量
SCRIPT_PATH="/usr/local/bin/delayed-routing.sh"
SERVICE_PATH="/etc/systemd/system/delayed-routing.service"

# 创建延时执行脚本
cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash
# 延时 30 秒后执行 systemd 命令
sleep 30
systemctl daemon-reload
systemctl restart multi-nic-routing.service
EOF

# 设置执行权限
chmod +x "$SCRIPT_PATH"

# 创建 systemd 服务文件
cat > "$SERVICE_PATH" << 'EOF'
[Unit]
Description=Delayed execution of multi-nic-routing.service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/delayed-routing.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd 并启用服务
systemctl daemon-reload
systemctl enable delayed-routing.service
systemctl start delayed-routing.service

echo "✅ 已成功安装并启用 delayed-routing.service，开机将延时执行重载并重启 multi-nic-routing.service。"
