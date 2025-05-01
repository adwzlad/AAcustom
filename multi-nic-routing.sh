#!/bin/bash
# 一键部署 Google Cloud 多网卡策略路由配置脚本（IPv4 + IPv6）
set -e

SERVICE_NAME="multi-nic-routing"
SYSTEMD_PATH="/etc/systemd/system/$SERVICE_NAME.service"
ROUTE_SCRIPT="/usr/local/bin/${SERVICE_NAME}.sh"
RT_TABLES_FILE="/etc/iproute2/rt_tables"

echo "📦 写入策略路由主脚本..."
cat > "$ROUTE_SCRIPT" <<'EOF'
#!/bin/bash
set -e

# 安装 sipcalc 以支持 IPv6 子网解析
command -v sipcalc >/dev/null || {
  echo "📥 安装 sipcalc..."
  apt update && apt install -y sipcalc
}

echo "🧹 清除旧 IPv4 策略路由规则..."
ip rule | grep -E 'from 10\.' | while read -r line; do
  PRIO=$(echo "$line" | awk '{print $1}' | tr -d ':')
  [[ "$PRIO" =~ ^[0-9]+$ ]] && ip rule del prio "$PRIO" || true
done

echo "🧹 清除旧 IPv6 策略路由规则..."
ip -o -6 addr show scope global | awk '{print $4}' | while read -r IPADDR; do
  IP=$(echo "$IPADDR" | cut -d/ -f1)
  ip -6 rule | grep "$IP/128" | while read -r line; do
    PRIO=$(echo "$line" | awk '{print $1}' | tr -d ':')
    [[ "$PRIO" =~ ^[0-9]+$ ]] && ip -6 rule del prio "$PRIO" || true
  done
done

echo "🧹 清除旧的路由表..."
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
  ip route replace "$SUBNET" dev "$IFACE" src "$IP" table "$TABLE_NAME" || true
  ip route replace default via "$GATEWAY" dev "$IFACE" table "$TABLE_NAME" || true
  ip rule add from "$IP/32" table "$TABLE_NAME" priority "$TABLE_INDEX" || true

  sysctl -w "net.ipv4.conf.$IFACE.rp_filter=0" > /dev/null
  ((TABLE_INDEX++))

  #### IPv6 配置
  IPV6_INFO=$(ip -o -6 addr show dev "$IFACE" scope global | awk '{print $4}' | head -n1)
  if [ -n "$IPV6_INFO" ]; then
    IPV6_ADDR=$(echo "$IPV6_INFO" | cut -d/ -f1)
    PREFIX_LEN=$(echo "$IPV6_INFO" | cut -d/ -f2)
    SUBNET=$(sipcalc "$IPV6_ADDR/$PREFIX_LEN" | awk -F - '/Compressed/{getline; print $1}' | sed 's/ //g')"/$PREFIX_LEN"

    IPV6_GW=$(ip -6 route show dev "$IFACE" | grep ^default | awk '{print $3}')
    [ -z "$IPV6_GW" ] && IPV6_GW="${SUBNET%::*}::1"

    ip -6 route replace "$SUBNET" dev "$IFACE" table "$TABLE_NAME" || true
    ip -6 route replace default via "$IPV6_GW" dev "$IFACE" table "$TABLE_NAME" || true
    ip -6 rule add from "$IPV6_ADDR/128" table "$TABLE_NAME" priority "$TABLE_INDEX" || true
  fi
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
