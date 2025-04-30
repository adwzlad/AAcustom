#!/bin/bash
# 适用于 GCP VM，自动为多个 NIC 设置出入站策略路由并保持重启后生效

set -e

SERVICE_NAME="multi-nic-routing"
SYSTEMD_PATH="/etc/systemd/system/$SERVICE_NAME.service"
ROUTE_SCRIPT="/usr/local/bin/${SERVICE_NAME}.sh"

echo "🔍 正在识别所有 GCP 网络接口..."

# 获取所有非回环、有 10.x IP 的接口
NIC_INFOS=$(ip -o -4 addr show | grep '10\.' | awk '{print $2, $4}')
if [ -z "$NIC_INFOS" ]; then
  echo "❌ 未找到符合条件的 NIC（10.x 网段）。"
  exit 1
fi

echo "✅ 发现以下接口："
echo "$NIC_INFOS"

echo "📄 写入策略路由表配置..."
RT_TABLES_FILE="/etc/iproute2/rt_tables"
TABLE_INDEX=100

while read -r IFACE IPADDR; do
  TABLE_NAME="rt_${IFACE}"
  if ! grep -q "$TABLE_NAME" $RT_TABLES_FILE; then
    echo "$TABLE_INDEX $TABLE_NAME" | sudo tee -a $RT_TABLES_FILE
    ((TABLE_INDEX++))
  fi
done <<< "$NIC_INFOS"

echo "⚙️ 生成永久性策略路由脚本：$ROUTE_SCRIPT"

# 写入实际路由脚本
sudo bash -c "cat > $ROUTE_SCRIPT" <<EOF
#!/bin/bash
# 自动设置所有接口的策略路由

set -e

# 清理旧规则
ip rule | grep 'from 10\.' | while read -r line; do
  PRIO=\$(echo \$line | awk '{print \$1}')
  ip rule del prio \$PRIO || true
done

NIC_INFOS=\$(ip -o -4 addr show | grep '10\.' | awk '{print \$2, \$4}')

while read -r IFACE IPADDR; do
  IP=\$(echo \$IPADDR | cut -d/ -f1)
  PREFIX=\$(echo \$IPADDR | cut -d/ -f2)
  SUBNET=\$(ipcalc -n \$IP/\$PREFIX | grep Network | awk '{print \$2}')
  GATEWAY=\$(ip route show dev \$IFACE | grep default | awk '{print \$3}')
  [ -z "\$GATEWAY" ] && GATEWAY=\$(echo \$SUBNET | sed 's|0/.*|1|')

  TABLE_NAME="rt_\$IFACE"

  echo "🔁 配置接口 \$IFACE（\$IP）使用路由表 \$TABLE_NAME"

  ip route add \$SUBNET dev \$IFACE src \$IP table \$TABLE_NAME || true
  ip route add default via \$GATEWAY dev \$IFACE table \$TABLE_NAME || true
  ip rule add from \$IP/32 table \$TABLE_NAME priority 1000 || true

  sysctl -w net.ipv4.conf.\$IFACE.rp_filter=0
done <<< "\$NIC_INFOS"

sysctl -w net.ipv4.conf.all.rp_filter=0
EOF

sudo chmod +x $ROUTE_SCRIPT

echo "🧩 创建 systemd 服务：$SERVICE_NAME"

sudo bash -c "cat > $SYSTEMD_PATH" <<EOF
[Unit]
Description=Multi-NIC Policy Routing Setup
After=network.target

[Service]
Type=oneshot
ExecStart=$ROUTE_SCRIPT
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now $SERVICE_NAME

echo "✅ 所有策略路由已配置并永久生效！"
echo "📦 systemd 服务：$SERVICE_NAME"
