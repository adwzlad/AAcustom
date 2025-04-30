#!/bin/bash
# 一键部署 Google Cloud 多网卡策略路由配置脚本
set -e

SERVICE_NAME="multi-nic-routing"
SYSTEMD_PATH="/etc/systemd/system/$SERVICE_NAME.service"
ROUTE_SCRIPT="/usr/local/bin/${SERVICE_NAME}.sh"
RT_TABLES_FILE="/etc/iproute2/rt_tables"

echo "📦 写入策略路由主脚本..."
cat > "$ROUTE_SCRIPT" <<'EOF'
#!/bin/bash
set -e

echo "🧹 清除旧的规则和路由表..."
ip rule | grep 'from 10\.' | while read -r line; do
  PRIO=$(echo $line | awk '{print $1}')
  ip rule del prio $PRIO || true
done

for TABLE in $(grep '^1[0-9][0-9] rt_' /etc/iproute2/rt_tables | awk '{print $2}'); do
  ip route flush table $TABLE || true
done

NIC_INFOS=$(ip -o -4 addr show | grep '10\.' | awk '{print $2, $4}')
echo "$NIC_INFOS" | while read -r IFACE IPADDR; do
  IP=$(echo $IPADDR | cut -d/ -f1)
  PREFIX=$(echo $IPADDR | cut -d/ -f2)
  SUBNET=$(ipcalc -n $IP/$PREFIX | grep Network | awk '{print $2}')

  GATEWAY=$(ip route | grep "^default.*dev $IFACE" | awk '{print $3}')
  [ -z "$GATEWAY" ] && GATEWAY=$(echo $SUBNET | sed 's|0/.*|1|')

  TABLE_NAME="rt_$IFACE"
  ip route replace $SUBNET dev $IFACE src $IP table $TABLE_NAME || true
  ip route replace default via $GATEWAY dev $IFACE table $TABLE_NAME || true

  ip rule | grep -q "from $IP/32 table $TABLE_NAME" || \
    ip rule add from $IP/32 table $TABLE_NAME priority 1000

  sysctl -w net.ipv4.conf.$IFACE.rp_filter=0 > /dev/null
done

sysctl -w net.ipv4.conf.all.rp_filter=0 > /dev/null

echo "🧪 验证配置："
echo -e "\n🔍 当前策略路由规则："
ip rule | grep 'from 10\.' || echo "⚠️ 无策略路由规则"

echo -e "\n📜 当前路由表定义："
grep '^1[0-9][0-9] rt_' /etc/iproute2/rt_tables

echo -e "\n📤 路由表内容："
for TABLE in $(grep '^1[0-9][0-9] rt_' /etc/iproute2/rt_tables | awk '{print $2}'); do
  echo -e "\n🧭 表 $TABLE:"
  ip route show table $TABLE
done

echo -e "\n🌐 Ping 测试："
echo "$NIC_INFOS" | while read -r IFACE IPADDR; do
  IP=$(echo $IPADDR | cut -d/ -f1)
  echo -n "📡 $IFACE ($IP)："
  ping -c 1 -W 2 -I $IP 8.8.8.8 &>/dev/null && echo "✅ 通！" || echo "❌ 不通！" &
done
wait
EOF

chmod +x "$ROUTE_SCRIPT"

echo "🔁 更新 /etc/iproute2/rt_tables..."
sed -i '/^1[0-9][0-9] rt_/d' "$RT_TABLES_FILE"
TABLE_INDEX=100
NIC_INFOS=$(ip -o -4 addr show | grep '10\.' | awk '{print $2, $4}')
while read -r IFACE IPADDR; do
  echo "$TABLE_INDEX rt_$IFACE" >> "$RT_TABLES_FILE"
  ((TABLE_INDEX++))
done <<< "$NIC_INFOS"

echo "🧩 写入 systemd 服务..."
cat > "$SYSTEMD_PATH" <<EOF
[Unit]
Description=Multi-NIC Policy Routing Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$ROUTE_SCRIPT
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

echo "🚀 启用服务并立即执行..."
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

echo "✅ 部署完成！"
