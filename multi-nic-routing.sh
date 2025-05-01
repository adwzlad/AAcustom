#!/bin/bash
# 一键部署 Google Cloud 多网卡策略路由配置脚本 (支持 IPv4 + IPv6)
set -e

SERVICE_NAME="multi-nic-routing"
SYSTEMD_PATH="/etc/systemd/system/$SERVICE_NAME.service"
ROUTE_SCRIPT="/usr/local/bin/${SERVICE_NAME}.sh"
RT_TABLES_FILE="/etc/iproute2/rt_tables"

echo "📦 安装依赖..."
apt update && apt install -y sipcalc

echo "📦 写入策略路由主脚本..."
cat > "$ROUTE_SCRIPT" <<'EOF'
#!/bin/bash
set -e

echo "🧹 清除旧的规则和路由表..."

# 清除 IPv4 规则和表
ip rule | grep -E 'from 10\.' | while read -r line; do
  PRIO=$(echo "$line" | awk '{print $1}' | tr -d ':')
  [[ "$PRIO" =~ ^[0-9]+$ ]] && ip rule del prio "$PRIO" || true
done

for TABLE in $(grep -E '^1[0-9][0-9] rt_' /etc/iproute2/rt_tables | awk '{print $2}'); do
  ip route flush table "$TABLE" || true
  ip -6 route flush table "$TABLE" || true
done

NIC_INFOS=$(ip -o -4 addr show | grep '10\.' | awk '{print $2, $4}')
TABLE_INDEX=1000

echo "$NIC_INFOS" | while read -r IFACE IPADDR; do
  IP=$(echo "$IPADDR" | cut -d/ -f1)
  SUBNET=$(ip route | grep "$IFACE" | grep -v 'default' | awk '{print $1}' | head -n1)
  GATEWAY=$(ip route | grep "^default.*dev $IFACE" | awk '{print $3}')
  [ -z "$GATEWAY" ] && GATEWAY="${SUBNET%.*}.1"

  TABLE_NAME="rt_$IFACE"
  ip route replace "$SUBNET" dev "$IFACE" src "$IP" table "$TABLE_NAME"
  ip route replace default via "$GATEWAY" dev "$IFACE" table "$TABLE_NAME"

  ip rule add from "$IP/32" table "$TABLE_NAME" priority "$TABLE_INDEX" || true
  sysctl -w "net.ipv4.conf.$IFACE.rp_filter=0" > /dev/null

  # === IPv6 ===
  IPV6=$(ip -6 addr show dev "$IFACE" scope global | grep -v "deprecated" | awk '/inet6/ {print $2}' | head -n1)
  [ -z "$IPV6" ] && continue
  IPV6_ADDR=$(echo "$IPV6" | cut -d/ -f1)
  IPV6_SUBNET=$(sipcalc "$IPV6" | awk -F - '/Compressed/ {getline; print $1}' | xargs)

  # 获取本接口的 link-local 网关
  LLGW=$(ip -6 neigh show dev "$IFACE" | awk '/fe80::/ {print $1; exit}')
  [ -z "$LLGW" ] && LLGW="fe80::1"

  ip -6 route add default via "$LLGW" dev "$IFACE" table "$TABLE_NAME" || true
  ip -6 rule add from "$IPV6_ADDR/128" table "$TABLE_NAME" priority "$TABLE_INDEX" || true

  ((TABLE_INDEX++))
done

sysctl -w net.ipv4.conf.all.rp_filter=0 > /dev/null

echo "✅ 策略路由配置完成！"
EOF

chmod +x "$ROUTE_SCRIPT"

echo "🔁 更新 /etc/iproute2/rt_tables..."
sed -i '/^1[0-9][0-9] rt_/d' "$RT_TABLES_FILE"
TABLE_INDEX=100
while read -r IFACE _; do
  echo "$TABLE_INDEX rt_$IFACE" >> "$RT_TABLES_FILE"
  ((TABLE_INDEX++))
done <<< "$(ip -o -4 addr show | grep '10\.' | awk '{print $2, $4}')"

echo "🧩 写入 systemd 服务..."
cat > "$SYSTEMD_PATH" <<EOF
[Unit]
Description=Multi-NIC Policy Routing Setup (IPv4 + IPv6)
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
