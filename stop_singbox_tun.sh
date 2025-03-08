#!/bin/sh

echo "正在停止 Sing-box..."

# 杀死 Sing-box 进程
pkill -f "sing-box"

# 等待进程完全退出
sleep 2

# 获取 OpenWrt 的 LAN IP 和子网掩码
LAN_IP=$(uci get network.lan.ipaddr)
LAN_NETMASK=$(uci get network.lan.netmask)

# 计算 LAN 网段（仅适用于 /24 子网掩码）
LAN_SUBNET=$(echo "$LAN_IP" | awk -F. '{print $1"."$2"."$3".0/24"}')

# 获取 TUN 设备名称
TUN_IFACE=$(ip link | awk -F: '/tun/ {print $2; exit}' | tr -d ' ')

if [ -z "$TUN_IFACE" ]; then
    echo "未检测到 TUN 设备，可能已经停止。"
else
    echo "检测到 TUN 设备: $TUN_IFACE，正在清理路由规则..."

    # 移除路由规则
    ip rule del from "$LAN_SUBNET" table 100 2>/dev/null
    ip route del default dev "$TUN_IFACE" table 100 2>/dev/null
fi

echo "清理防火墙规则..."

# 移除 NAT 伪装规则
uci delete firewall.singtun 2>/dev/null
uci delete firewall.@rule[-1] 2>/dev/null
uci commit firewall
service firewall restart

echo "清理开机启动项..."

# 从 /etc/rc.local 移除相关规则
sed -i '/ip route add default dev/d' /etc/rc.local
sed -i '/ip rule add from/d' /etc/rc.local

echo "Sing-box 已停止，TUN 规则已清理！"
