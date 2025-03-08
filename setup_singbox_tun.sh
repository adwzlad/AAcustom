#!/bin/sh

# 获取 OpenWrt 的 LAN IP 和子网掩码
LAN_IP=$(uci get network.lan.ipaddr)
LAN_NETMASK=$(uci get network.lan.netmask)

# 计算 LAN 网段（仅适用于 /24 子网掩码）
LAN_SUBNET=$(echo "$LAN_IP" | awk -F. '{print $1"."$2"."$3".0/24"}')

# **启动 Sing-box**
echo "启动 Sing-box..."
sing-box run -c /etc/singbox.config &  # 后台运行

# **等待 TUN 设备创建**
echo "等待 TUN 设备创建..."
for i in {1..10}; do
    TUN_IFACE=$(ip link | awk -F: '/tun/ {print $2; exit}' | tr -d ' ')
    if [ -n "$TUN_IFACE" ]; then
        echo "检测到 TUN 设备: $TUN_IFACE"
        break
    fi
    sleep 1
done

# 如果 10 秒后仍未检测到 TUN，退出
if [ -z "$TUN_IFACE" ]; then
    echo "错误: 未检测到 TUN 设备，Sing-box 可能未正确启动！"
    exit 1
fi

# **配置防火墙**
echo "配置防火墙..."
uci set firewall.singtun=zone
uci set firewall.singtun.name='singtun'
uci set firewall.singtun.input='ACCEPT'
uci set firewall.singtun.output='ACCEPT'
uci set firewall.singtun.forward='ACCEPT'
uci set firewall.singtun.network="$TUN_IFACE"

uci add firewall rule
uci set firewall.@rule[-1].src="$TUN_IFACE"
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall
service firewall restart

# **设置路由**
echo "配置路由..."
ip route add default dev "$TUN_IFACE" table 100
ip rule add from "$LAN_SUBNET" table 100

# **确保规则持久化**
sed -i '/ip route add default dev/d' /etc/rc.local
sed -i '/ip rule add from/d' /etc/rc.local
echo "ip route add default dev $TUN_IFACE table 100" >> /etc/rc.local
echo "ip rule add from $LAN_SUBNET table 100" >> /etc/rc.local
chmod +x /etc/rc.local

echo "Sing-box 配置完成！"
