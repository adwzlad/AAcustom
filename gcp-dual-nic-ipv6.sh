#!/bin/bash
# GCP 双网卡 IPv4+IPv6 自动策略路由设置（支持重启），适配 ens4 / ens5 接口
# 作者：https://github.com/adwzlad/AAcustom

set -e

echo "==> 安装 sipcalc ..."
apt update -y && apt install -y sipcalc

echo "==> 写入主路由脚本 ..."
cat > /usr/local/bin/multi-nic-routing.sh << 'EOF'
#!/bin/bash
set -e

command -v sipcalc >/dev/null 2>&1 || apt install -y sipcalc
interfaces=("ens4" "ens5")

# 清理旧规则和路由
ip -4 rule | grep -E "lookup rt_ens[45]" | while read -r line; do ip -4 rule del priority $(echo $line | awk '{print $1}'); done
ip -6 rule | grep -E "lookup rt_ens[45]" | while read -r line; do ip -6 rule del priority $(echo $line | awk '{print $1}'); done
ip route flush table rt_ens4 2>/dev/null || true
ip route flush table rt_ens5 2>/dev/null || true
ip -6 route flush table rt_ens4 2>/dev/null || true
ip -6 route flush table rt_ens5 2>/dev/null || true

for iface in "${interfaces[@]}"; do
  table="rt_$iface"
  ipv4=$(ip -4 addr show dev "$iface" | awk '/inet / {print $2}' | head -n1)
  gateway4=$(ip route | grep "default via" | grep "$iface" | awk '{print $3}' | head -n1)
  if [[ -n $ipv4 && -n $gateway4 ]]; then
    ip rule add from "${ipv4%%/*}" table "$table" priority $((1000 + ${iface: -1}))
    ip route add default via "$gateway4" dev "$iface" table "$table"
  fi

  ipv6=$(ip -6 addr show dev "$iface" | awk '/inet6 [2]/ {print $2}' | head -n1)
  if [[ -n $ipv6 ]]; then
    gw6=$(ip -6 neigh show dev "$iface" | grep "router" | awk '{print $1}' | head -n1)
    prefix6=$(sipcalc "$ipv6" | awk -F - '/Compressed/ {print $2}' | xargs | cut -d'/' -f1)/65
    ip -6 rule add from "${ipv6%%/*}" table "$table" priority $((1000 + ${iface: -1}))
    [[ -n $gw6 ]] && ip -6 route add "$prefix6" via "$gw6" dev "$iface" table "$table"
    [[ -n $gw6 ]] && ip -6 route add default via "$gw6" dev "$iface" table "$table"
  fi
done
EOF

chmod +x /usr/local/bin/multi-nic-routing.sh

echo "==> 写入等待邻居脚本 ..."
cat > /usr/local/bin/wait-for-nic.sh << 'EOF'
#!/bin/bash
for dev in ens4 ens5; do
  echo "等待 $dev 的 IPv6 邻居 router 可用..."
  for i in {1..15}; do
    if ip -6 neigh show dev "$dev" | grep -q "router"; then
      echo "$dev 已就绪。"
      break
    fi
    sleep 2
  done
done
EOF

chmod +x /usr/local/bin/wait-for-nic.sh

echo "==> 写入 systemd 服务 ..."
cat > /etc/systemd/system/multi-nic-routing.service << 'EOF'
[Unit]
Description=Multi-NIC Routing Configuration with IPv6 Neighbor Delay
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/usr/local/bin/wait-for-nic.sh
ExecStart=/usr/local/bin/multi-nic-routing.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo "==> 启用服务并立即执行 ..."
systemctl daemon-reload
systemctl enable multi-nic-routing.service
systemctl start multi-nic-routing.service

echo "✅ GCP 双网卡策略路由配置完成。建议重启测试是否生效。"
