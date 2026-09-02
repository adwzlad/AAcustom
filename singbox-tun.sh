#!/bin/bash
set -e

VERSION="2.1"

BASE_DIR="/root/singbox"
BIN="$BASE_DIR/sing-box"
CONFIG="$BASE_DIR/config.json"

mkdir -p "$BASE_DIR"

echo "================================"
echo " Sing-box TUN $VERSION"
echo " sing-box latest"
echo " Node DNS : 1.1.1.1"
echo " Client DNS : 223.5.5.5"
echo " SSH bypass : 22"
echo " Temporary mode"
echo "================================"


if [ "$(id -u)" != "0" ]; then
    echo "请使用root运行"
    exit 1
fi


if pgrep -x sing-box >/dev/null; then
    echo "已有sing-box运行"
    exit 1
fi


apt_update()
{
    apt update -qq
    apt install -y \
    curl wget unzip jq dnsutils iproute2 procps >/dev/null
}


for i in curl wget jq dig
do
    command -v $i >/dev/null 2>&1 || apt_update
done


ARCH=$(uname -m)

case "$ARCH" in
x86_64)
    SB_ARCH="amd64"
    ;;
aarch64|arm64)
    SB_ARCH="arm64"
    ;;
*)
    echo "不支持架构 $ARCH"
    exit 1
    ;;
esac



if [ ! -x "$BIN" ]; then

    echo "下载最新版sing-box"

    TAG=$(curl -s \
    https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | jq -r .tag_name)


    FILE="sing-box-${TAG#v}-linux-${SB_ARCH}.tar.gz"


    wget -q \
    "https://github.com/SagerNet/sing-box/releases/download/$TAG/$FILE" \
    -O /tmp/$FILE


    tar xf /tmp/$FILE -C /tmp


    DIR=$(find /tmp -maxdepth 1 -type d \
    -name "sing-box-*" | head -1)


    cp "$DIR/sing-box" "$BIN"

    chmod +x "$BIN"

fi


$BIN version



echo
read -rp "请输入 anytls/tuic 节点URL: " NODE_URL


case "$NODE_URL" in
anytls://*)
    TYPE="anytls"
    ;;
tuic://*)
    TYPE="tuic"
    ;;
*)
    echo "只支持anytls/tuic"
    exit 1
    ;;
esac



RAW="${NODE_URL#*://}"

RAW="${RAW%%#*}"

MAIN="${RAW%%\?*}"

QUERY=""

if [[ "$RAW" == *"?"* ]]; then
    QUERY="${RAW#*\?}"
fi


USERINFO="${MAIN%@*}"
HOSTPORT="${MAIN##*@}"



if [[ "$HOSTPORT" =~ ^\[.*\]:[0-9]+$ ]]; then

    SERVER="${HOSTPORT%%]*}"
    SERVER="${SERVER#\[}"

    PORT="${HOSTPORT##*:}"


else

    SERVER="${HOSTPORT%:*}"
    PORT="${HOSTPORT##*:}"

fi



echo
echo "类型: $TYPE"
echo "服务器: $SERVER"
echo "端口: $PORT"



get_param()
{
echo "$QUERY" | tr '&' '\n' \
| grep "^$1=" \
| cut -d '=' -f2- \
| head -1
}


SNI=$(get_param sni)

INSECURE=$(get_param insecure)

ALPN=$(get_param alpn)

CONGESTION=$(get_param congestion_control)



echo "解析节点完成"

cat > "$CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },

  "dns": {
    "servers": [
      {
        "tag": "dns-node",
        "address": "https://1.1.1.1/dns-query",
        "detour": "direct"
      },
      {
        "tag": "dns-proxy",
        "address": "udp://223.5.5.5",
        "detour": "proxy"
      }
    ],
    "rules": [
      {
        "server": "dns-node",
        "domain_suffix": [
          "$SERVER"
        ]
      },
      {
        "server": "dns-proxy",
        "rule_set": []
      }
    ],
    "final": "dns-proxy"
  },


  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "singtun",
      "inet4_address": "172.19.0.1/30",
      "inet6_address": "fdfe:dcba:9876::1/126",
      "auto_route": true,
      "strict_route": true,
      "stack": "system"
    }
  ],


  "outbounds": [

EOF



if [ "$TYPE" = "anytls" ]; then


UUID=$(echo "$USERINFO" | cut -d: -f1)
PASS=$(echo "$USERINFO" | cut -d: -f2)


cat >> "$CONFIG" <<EOF
    {
      "type": "anytls",
      "tag": "proxy",
      "server": "$SERVER",
      "server_port": $PORT,
      "password": "$USERINFO",

      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "insecure": true,
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        }
      },

      "domain_resolver": "dns-node"
    },

EOF



else


UUID=$(echo "$USERINFO" | cut -d: -f1)
PASS=$(echo "$USERINFO" | cut -d: -f2)


cat >> "$CONFIG" <<EOF
    {
      "type": "tuic",
      "tag": "proxy",

      "server": "$SERVER",
      "server_port": $PORT,

      "uuid": "$UUID",
      "password": "$PASS",

      "congestion_control": "${CONGESTION:-bbr}",

      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "insecure": true,
        "alpn": [
          "h3"
        ]
      },

      "domain_resolver": "dns-node"
    },

EOF


fi



cat >> "$CONFIG" <<EOF

    {
      "type": "direct",
      "tag": "direct"
    }

  ],


  "route": {

    "auto_detect_interface": true,

    "rules": [

      {
        "protocol": "dns",
        "action": "hijack-dns"
      },


      {
        "port": 22,
        "outbound": "direct"
      }

    ],

    "final": "proxy",

    "default_domain_resolver": "dns-node"
  }

}

EOF



echo
echo "配置生成完成"

echo
echo "检查 sing-box 配置"

$BIN check -c "$CONFIG"

echo
echo "配置正常"


echo
echo "启动 TUN..."

mkdir -p /etc/systemd/system

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box TUN Proxy
After=network-online.target
Wants=network-online.target


[Service]
Type=simple

ExecStart=$BIN run -c $CONFIG

Restart=always
RestartSec=5

LimitNOFILE=1048576


[Install]
WantedBy=multi-user.target

EOF



systemctl daemon-reload

systemctl enable sing-box >/dev/null 2>&1

systemctl restart sing-box



sleep 5



echo
echo "检查运行状态"

if systemctl is-active --quiet sing-box; then

    echo
    echo "================================"
    echo " sing-box TUN 启动成功"
    echo "================================"
    echo
    echo "节点:"
    echo "$SERVER:$PORT"
    echo
    echo "SSH端口 22 已直连保护"
    echo "其它IPv4/IPv6流量全部接管"
    echo
    echo "DNS:"
    echo "节点解析 -> 1.1.1.1"
    echo "代理DNS -> 223.5.5.5"
    echo

else

    echo
    echo "启动失败"
    echo
    echo "恢复网络..."

    systemctl stop sing-box

    ip rule del table 2022 2>/dev/null || true
    ip route flush table 2022 2>/dev/null || true

    echo
    echo "请检查:"
    echo "$CONFIG"
    echo

    exit 1

fi



echo
echo "实时日志:"
echo "Ctrl+C退出日志，不停止服务"

journalctl -u sing-box -f
