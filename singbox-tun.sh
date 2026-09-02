#!/bin/bash
set -e

VERSION="3.0"

INSTALL_DIR="/root/singbox"
BIN="/usr/local/bin/sing-box"
CONFIG="$INSTALL_DIR/config.json"

mkdir -p "$INSTALL_DIR"

clear

echo "================================"
echo " Sing-box TUN $VERSION"
echo " sing-box latest"
echo " Node DNS : 1.1.1.1"
echo " Client DNS : 223.5.5.5"
echo " SSH bypass : 22"
echo "================================"


ARCH=$(uname -m)

case "$ARCH" in
    x86_64)
        SB_ARCH="amd64"
        ;;
    aarch64|arm64)
        SB_ARCH="arm64"
        ;;
    *)
        echo "不支持架构: $ARCH"
        exit 1
        ;;
esac


echo
echo "系统架构:"
echo "$ARCH"



if command -v sing-box >/dev/null 2>&1; then

    BIN=$(command -v sing-box)

    echo
    echo "发现已有 sing-box:"
    $BIN version | head -1

else

    echo
    echo "安装最新版 sing-box"

    TMP=$(mktemp -d)

    URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | grep browser_download_url \
    | grep linux-${SB_ARCH} \
    | head -1 \
    | cut -d '"' -f4)

    if [ -z "$URL" ]; then
        echo "获取最新版失败"
        exit 1
    fi


    wget -q "$URL" -O "$TMP/singbox.tar.gz"

    tar xf "$TMP/singbox.tar.gz" -C "$TMP"

    cp $(find "$TMP" -name sing-box -type f | head -1) "$BIN"

    chmod +x "$BIN"

fi



echo
echo "请输入 anytls/tuic 节点URL:"
read -r NODE_URL


case "$NODE_URL" in

    anytls://*)
        TYPE="anytls"
        ;;

    tuic://*)
        TYPE="tuic"
        ;;

    *)
        echo "只支持 anytls:// 和 tuic://"
        exit 1
        ;;

esac



echo
echo "解析节点..."

TMPURL="${NODE_URL#*://}"

NODE_MAIN="${TMPURL%%#*}"

AUTH_HOST="${NODE_MAIN%@*}"

SERVER_PORT="${NODE_MAIN#*@}"

SERVER="${SERVER_PORT%%:*}"

PORT_QUERY="${SERVER_PORT#*:}"

PORT="${PORT_QUERY%%\?*}"

PARAM="${NODE_URL#*\?}"

PARAM="${PARAM%%#*}"



echo
echo "类型:"
echo "$TYPE"

echo "服务器:"
echo "$SERVER"

echo "端口:"
echo "$PORT"



SNI=$(echo "$NODE_URL" \
| sed -n 's/.*sni=\([^&]*\).*/\1/p')


if [ -z "$SNI" ]; then
    SNI="$SERVER"
fi



echo
echo "检测节点DNS..."

NODE_IP=$(getent ahosts "$SERVER" \
| awk '{print $1}' \
| head -1 || true)


if [ -n "$NODE_IP" ]; then

echo "解析:"
echo "$NODE_IP"

else

echo "DNS解析失败"
exit 1

fi



cat > "$INSTALL_DIR/node.env" <<EOF
TYPE=$TYPE
SERVER=$SERVER
PORT=$PORT
SNI=$SNI
NODE_URL=$NODE_URL
EOF


echo
echo "节点解析完成"

source "$INSTALL_DIR/node.env"


cat > "$CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },


  "dns": {

    "servers": [

      {
        "type": "https",
        "tag": "dns-node",
        "server": "1.1.1.1",
        "path": "/dns-query",
        "detour": "direct"
      },


      {
        "type": "udp",
        "tag": "dns-proxy",
        "server": "223.5.5.5",
        "detour": "proxy"
      }

    ],


    "rules": [

      {
        "domain": [
          "$SERVER"
        ],
        "server": "dns-node"
      }

    ],


    "final": "dns-proxy"

  },


  "inbounds": [

    {
      "type": "tun",
      "tag": "tun-in",

      "interface_name": "singtun",

      "address": [
        "172.19.0.1/30",
        "fdfe:dcba:9876::1/126"
      ],

      "auto_route": true,

      "strict_route": true,

      "stack": "system"
    }

  ],


  "outbounds": [

EOF



if [ "$TYPE" = "anytls" ]; then


cat >> "$CONFIG" <<EOF

    {

      "type": "anytls",

      "tag": "proxy",

      "server": "$SERVER",

      "server_port": $PORT,

      "password": "${NODE_URL#*://}",


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


elif [ "$TYPE" = "tuic" ]; then


UUID_PASS="${AUTH_HOST}"

UUID="${UUID_PASS%%:*}"

PASSWORD="${UUID_PASS#*:}"


cat >> "$CONFIG" <<EOF

    {

      "type": "tuic",

      "tag": "proxy",

      "server": "$SERVER",

      "server_port": $PORT,

      "uuid": "$UUID",

      "password": "$PASSWORD",


      "congestion_control": "bbr",


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
echo "启动 sing-box TUN..."

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


echo
echo "启动服务..."

systemctl restart sing-box



sleep 5



echo
echo "检测运行状态"



if systemctl is-active --quiet sing-box; then


    echo
    echo "================================"
    echo " Sing-box TUN 启动成功"
    echo "================================"

    echo
    echo "节点:"
    echo "$TYPE://$SERVER:$PORT"

    echo
    echo "DNS策略:"
    echo "节点域名解析 -> 1.1.1.1 DoH"

    echo "代理流量DNS -> 223.5.5.5"

    echo
    echo "SSH 22:"
    echo "直连保护"

    echo
    echo "IPv4:"
    echo "支持"

    echo "IPv6:"
    echo "支持"

    echo
    echo "所有其它流量:"
    echo "进入 TUN -> proxy"



else


    echo
    echo "sing-box启动失败"

    echo
    echo "恢复网络"


    systemctl stop sing-box || true


    ip rule del table 2022 2>/dev/null || true

    ip route flush table 2022 2>/dev/null || true


    echo

    echo "失败日志:"

    journalctl -u sing-box -n 50 --no-pager


    exit 1


fi



echo

echo "实时日志"

echo "Ctrl+C 只退出日志，不停止服务"

echo


journalctl -u sing-box -f
