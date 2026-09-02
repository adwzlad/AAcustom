#!/bin/bash
set -e

VERSION="3.1"

INSTALL_DIR="/root/singbox"
CONFIG="$INSTALL_DIR/config.json"
ENV_FILE="$INSTALL_DIR/node.env"

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


    BIN="/usr/local/bin/sing-box"

    echo
    echo "安装最新版 sing-box"


    TMP=$(mktemp -d)


    TAG=$(curl -s \
    https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | jq -r '.tag_name')


    FILE="sing-box-${TAG#v}-linux-${SB_ARCH}.tar.gz"


    wget -q \
    "https://github.com/SagerNet/sing-box/releases/download/$TAG/$FILE" \
    -O "$TMP/$FILE"


    tar xf "$TMP/$FILE" -C "$TMP"


    cp "$(find "$TMP" -name sing-box -type f | head -1)" "$BIN"


    chmod +x "$BIN"


fi



echo

$BIN version | head -3



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
    echo "只支持 anytls:// 和 tuic://"
    exit 1
    ;;

esac



echo

echo "解析节点..."



TMPURL="${NODE_URL#*://}"

NO_HASH="${TMPURL%%#*}"

AUTH_HOST="${NO_HASH%@*}"

SERVER_PORT="${NO_HASH#*@}"



SERVER="${SERVER_PORT%%:*}"

PORT_TMP="${SERVER_PORT#*:}"

PORT="${PORT_TMP%%\?*}"



QUERY=""

if [[ "$NODE_URL" == *"?"* ]]; then

    QUERY="${NODE_URL#*\?}"
    QUERY="${QUERY%%#*}"

fi



get_param()
{

echo "$QUERY" \
| tr '&' '\n' \
| grep "^$1=" \
| cut -d '=' -f2- \
| head -1

}



SNI=$(get_param sni)


if [ -z "$SNI" ]; then

SNI="$SERVER"

fi



echo
echo "类型:"
echo "$TYPE"

echo "服务器:"
echo "$SERVER"

echo "端口:"
echo "$PORT"



echo

echo "检测节点DNS..."

NODE_IP=$(dig @1.1.1.1 +short "$SERVER" \
| grep -E '^[0-9a-fA-F:.]+$' \
| head -1 || true)



if [ -z "$NODE_IP" ]; then

echo "节点DNS解析失败"

exit 1

fi



echo "解析:"
echo "$NODE_IP"



cat > "$ENV_FILE" <<EOF
TYPE=$TYPE
SERVER=$SERVER
PORT=$PORT
SNI=$SNI
AUTH_HOST=$AUTH_HOST
NODE_URL=$NODE_URL
EOF



echo

echo "节点解析完成"

source "$ENV_FILE"


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
        "path": "/dns-query"
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

    {
      "type": "direct",
      "tag": "direct"
    },


EOF



if [ "$TYPE" = "anytls" ]; then


cat >> "$CONFIG" <<EOF

    {
      "type": "anytls",

      "tag": "proxy",

      "server": "$SERVER",

      "server_port": $PORT,

      "password": "$AUTH_HOST",


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

    }

EOF



elif [ "$TYPE" = "tuic" ]; then


UUID="${AUTH_HOST%%:*}"

PASSWORD="${AUTH_HOST#*:}"



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

    }

EOF


fi



cat >> "$CONFIG" <<EOF

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


    "default_domain_resolver": "dns-node",

    "final": "proxy"

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
    echo "$TYPE $SERVER:$PORT"


    echo

    echo "DNS:"
    echo "节点解析 : 1.1.1.1 DoH"

    echo "代理DNS : 223.5.5.5"


    echo

    echo "SSH:"
    echo "22 端口直连保护"


    echo

    echo "流量:"
    echo "IPv4 全接管"

    echo "IPv6 全接管"


    echo

    echo "日志:"
    echo "Ctrl+C 退出日志，不停止服务"



    journalctl -u sing-box -f



else


    echo

    echo "sing-box启动失败"


    echo

    echo "日志:"


    journalctl -u sing-box -n 80 --no-pager


    echo

    echo "恢复网络"



    systemctl stop sing-box || true


    exit 1


fi
