#!/bin/bash
set -e

# 自动安装依赖
for pkg in jq curl; do
    if ! command -v $pkg >/dev/null 2>&1; then
        echo "[INFO] 安装 $pkg..."
        apt update
        apt install -y $pkg
    fi
done

# 获取默认网卡
iface=$(ip route | awk '/^default/ {print $5; exit}')
[[ -z "$iface" ]] && { echo "[ERROR] 未找到默认网卡"; exit 1; }

# 获取 OCI 分配的所有 IPv6 地址
ipv6_list=($(curl -s http://169.254.169.254/opc/v2/vnics/ | jq -r '.[0].ipv6Addresses[].ipAddress'))
[[ ${#ipv6_list[@]} -eq 0 ]] && { echo "[ERROR] OCI 未返回 IPv6"; exit 1; }

# 获取默认 IPv6 网关
gw=$(ip -6 route | awk '/default/ {print $3; exit}')
[[ -z "$gw" ]] && gw="fe80::1"

# 清理旧 IPv6
ip -6 addr flush dev "$iface" scope global

# 绑定所有 IPv6
for ip in "${ipv6_list[@]}"; do
    ip -6 addr add "$ip/64" dev "$iface"
done

# 设置默认路由
ip -6 route add default via "$gw" dev "$iface" || true

# 持久化到 /etc/network/interfaces.d/ipv6.cfg
mkdir -p /etc/network/interfaces.d
{
    echo "auto $iface"
    echo "iface $iface inet6 static"
    echo "    address ${ipv6_list[0]}"
    echo "    netmask 64"
    echo "    gateway $gw"
    for ip in "${ipv6_list[@]:1}"; do
        echo "    up ip -6 addr add $ip/64 dev $iface"
    done
} > /etc/network/interfaces.d/ipv6.cfg

echo "[INFO] 已绑定 IPv6: ${ipv6_list[*]}"
echo "[INFO] 配置已写入 /etc/network/interfaces.d/ipv6.cfg，重启后仍生效"
