#!/usr/bin/env bash
# ==========================================================
# Sing-box TUN OneKey 2.0
#
# Support:
#   Ubuntu 22.04 / 24.04
#   Debian 12 / 13
#
# Protocol:
#   anytls://
#   tuic://
#
# Features:
#   - latest sing-box release auto download
#   - amd64 / arm64
#   - IPv4 / IPv6 node
#   - IPv6-only domain
#   - node DNS resolver: 1.1.1.1
#   - client DNS through proxy: 223.5.5.5
#   - SSH port bypass
#   - temporary mode
#
# ==========================================================

set -euo pipefail

VERSION="2.0"

BASE_DIR="/root/singbox"
BIN="$BASE_DIR/sing-box"
CONFIG="$BASE_DIR/config.json"

SSH_PORT=22

mkdir -p "$BASE_DIR"


echo
echo "================================"
echo " Sing-box TUN $VERSION"
echo " Latest Core"
echo " Node DNS     : 1.1.1.1"
echo " Client DNS   : 223.5.5.5"
echo " SSH bypass   : $SSH_PORT"
echo " Temporary    : ON"
echo "================================"
echo


# ----------------------------------------------------------
# root check
# ----------------------------------------------------------

if [ "$(id -u)" != "0" ]; then
    echo "必须使用 root 运行"
    exit 1
fi


# ----------------------------------------------------------
# check existing sing-box
# ----------------------------------------------------------

if pgrep -x sing-box >/dev/null 2>&1; then
    echo
    echo "检测到 sing-box 已运行"
    echo

    ps aux | grep sing-box | grep -v grep

    echo
    echo "请先停止已有实例"
    exit 1
fi


# ----------------------------------------------------------
# install dependency
# ----------------------------------------------------------

install_pkg()
{
    export DEBIAN_FRONTEND=noninteractive

    apt update -qq

    apt install -y -qq \
        curl \
        wget \
        unzip \
        ca-certificates \
        jq \
        dnsutils \
        iproute2 \
        procps >/dev/null
}


for p in curl wget unzip jq dig ip
do
    if ! command -v "$p" >/dev/null 2>&1
    then
        install_pkg
        break
    fi
done


# ----------------------------------------------------------
# detect architecture
# ----------------------------------------------------------

ARCH=$(uname -m)

case "$ARCH" in

x86_64)
    SB_ARCH="amd64"
    ;;

aarch64|arm64)
    SB_ARCH="arm64"
    ;;

*)
    echo "不支持架构:"
    echo "$ARCH"
    exit 1
    ;;

esac


echo
echo "系统架构:"
echo "$ARCH"
echo


# ----------------------------------------------------------
# download latest sing-box
# ----------------------------------------------------------

download_singbox()
{

    echo "获取 sing-box 最新稳定版..."


    TAG=$(curl -fsSL \
    https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | jq -r '.tag_name')


    if [ -z "$TAG" ] || [ "$TAG" = "null" ]
    then
        echo "无法获取最新版"
        exit 1
    fi


    echo "版本:"
    echo "$TAG"


    FILE="sing-box-${TAG#v}-linux-${SB_ARCH}.tar.gz"


    URL="https://github.com/SagerNet/sing-box/releases/download/${TAG}/${FILE}"


    TMP="/tmp/$FILE"


    echo "下载:"
    echo "$URL"


    wget -q --show-progress \
        "$URL" \
        -O "$TMP"



    rm -rf /tmp/sing-box-*


    tar xf "$TMP" -C /tmp


    DIR=$(find /tmp \
        -maxdepth 1 \
        -type d \
        -name "sing-box-*" \
        | head -n1)


    cp "$DIR/sing-box" "$BIN"


    chmod +x "$BIN"


}


if [ ! -x "$BIN" ]
then
    download_singbox
else
    echo
    echo "发现已有 sing-box:"
    "$BIN" version
    echo
fi


# ----------------------------------------------------------
# input node URL
# ----------------------------------------------------------

echo
echo "请输入 anytls/tuic 节点URL:"
echo

read -r NODE_URL


if [[ "$NODE_URL" != anytls://* ]] &&
   [[ "$NODE_URL" != tuic://* ]]
then

    echo
    echo "只支持:"
    echo "anytls://"
    echo "tuic://"
    exit 1

fi


echo
echo "解析节点..."

# ----------------------------------------------------------
# parse node url
# ----------------------------------------------------------

NODE_TYPE=""
SERVER=""
SERVER_PORT=""
USER=""
PASS=""

if [[ "$NODE_URL" == anytls://* ]]
then
    NODE_TYPE="anytls"

    TMP_URL="${NODE_URL#anytls://}"

    # remove fragment
    TMP_URL="${TMP_URL%%#*}"

    # get server part
    AUTH_HOST="${TMP_URL%%\?*}"

    USER="${AUTH_HOST%@*}"

    HOST_PORT="${AUTH_HOST##*@}"


elif [[ "$NODE_URL" == tuic://* ]]
then
    NODE_TYPE="tuic"

    TMP_URL="${NODE_URL#tuic://}"

    TMP_URL="${TMP_URL%%#*}"

    AUTH_HOST="${TMP_URL%%\?*}"

    USER="${AUTH_HOST%@*}"

    HOST_PORT="${AUTH_HOST##*@}"


fi


# ----------------------------------------------------------
# IPv4 / IPv6 / domain split
# ----------------------------------------------------------

if [[ "$HOST_PORT" =~ ^\[.*\]:[0-9]+$ ]]
then

    # IPv6 address

    SERVER="${HOST_PORT%%]*}"
    SERVER="${SERVER#\[}"

    SERVER_PORT="${HOST_PORT##*:}"

    SERVER_IS_IP6=1


elif [[ "$HOST_PORT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]
then

    SERVER="${HOST_PORT%:*}"
    SERVER_PORT="${HOST_PORT##*:}"

    SERVER_IS_IP6=0


else

    SERVER="${HOST_PORT%:*}"
    SERVER_PORT="${HOST_PORT##*:}"

    SERVER_IS_IP6=0

fi


echo
echo "节点类型:"
echo "$NODE_TYPE"

echo "服务器:"
echo "$SERVER"

echo "端口:"
echo "$SERVER_PORT"


# ----------------------------------------------------------
# verify domain by 1.1.1.1
# ----------------------------------------------------------

if [ "$SERVER_IS_IP6" = "0" ] &&
   ! [[ "$SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
then

    echo
    echo "检测节点DNS..."

    A_RECORD=$(dig @1.1.1.1 "$SERVER" A +short | head -n1 || true)

    AAAA_RECORD=$(dig @1.1.1.1 "$SERVER" AAAA +short | head -n1 || true)


    if [ -n "$A_RECORD" ]
    then
        echo "IPv4:"
        echo "$A_RECORD"
    fi


    if [ -n "$AAAA_RECORD" ]
    then
        echo "IPv6:"
        echo "$AAAA_RECORD"
    fi


    if [ -z "$A_RECORD" ] &&
       [ -z "$AAAA_RECORD" ]
    then
        echo
        echo "节点域名无法解析"
        exit 1
    fi

fi


# ----------------------------------------------------------
# extract query parameters
# ----------------------------------------------------------

QUERY=""

if [[ "$NODE_URL" == *"?"* ]]
then
    QUERY="${NODE_URL#*\?}"
    QUERY="${QUERY%%#*}"
fi


get_param()
{
    echo "$QUERY" \
    | tr '&' '\n' \
    | grep "^$1=" \
    | cut -d '=' -f2- \
    | head -n1
}


TLS_INSECURE=$(get_param insecure || true)

SNI=$(get_param sni || true)

ALPN=$(get_param alpn || true)

CONGESTION=$(get_param congestion_control || true)


# ----------------------------------------------------------
# generate outbound
# ----------------------------------------------------------

if [ "$NODE_TYPE" = "anytls" ]
then

cat > "$BASE_DIR/outbound.json" <<EOF
{
"type":"anytls",
"tag":"proxy",
"server":"$SERVER",
"server_port":$SERVER_PORT,
"password":"$USER",
"tls":{
  "enabled":true,
  "server_name":"${SNI:-$SERVER}",
  "insecure":$([ "$TLS_INSECURE" = "1" ] && echo true || echo false),
  "utls":{
     "enabled":true,
     "fingerprint":"chrome"
  }
},
"domain_resolver":"dns-node"
}
EOF


elif [ "$NODE_TYPE" = "tuic" ]
then


UUID="${USER%%:*}"
PASSWORD="${USER#*:}"


cat > "$BASE_DIR/outbound.json" <<EOF
{
"type":"tuic",
"tag":"proxy",
"server":"$SERVER",
"server_port":$SERVER_PORT,
"uuid":"$UUID",
"password":"$PASSWORD",
"congestion_control":"${CONGESTION:-bbr}",
"tls":{
 "enabled":true,
 "server_name":"${SNI:-$SERVER}",
 "insecure":$([ "$TLS_INSECURE" = "1" ] && echo true || echo false),
 "alpn":[
   "h3"
 ]
},
"domain_resolver":"dns-node"
}
EOF


fi


echo
echo "生成 outbound 完成"

# ----------------------------------------------------------
# generate sing-box config
# ----------------------------------------------------------

OUTBOUND=$(cat "$BASE_DIR/outbound.json")


cat > "$CONFIG" <<EOF
{
"log":{
 "level":"error"
},

"dns":{
 "servers":[
  {
   "tag":"dns-node",
   "address":"https://1.1.1.1/dns-query",
   "detour":"direct"
  },
  {
   "tag":"dns-proxy",
   "address":"https://223.5.5.5/dns-query",
   "detour":"proxy"
  }
 ],

 "rules":[
  {
   "domain_suffix":[
    "$SERVER"
   ],
   "server":"dns-node"
  }
 ],

 "final":"dns-proxy"
},


"inbounds":[
 {
  "type":"tun",
  "tag":"tun-in",
  "interface_name":"singtun",
  "address":[
    "172.19.0.1/30",
    "fd00::1/126"
  ],
  "auto_route":true,
  "strict_route":true,
  "stack":"mixed",
  "sniff":true
 }
],


"outbounds":[
 $OUTBOUND
 ,

 {
  "type":"direct",
  "tag":"direct"
 },

 {
  "type":"block",
  "tag":"block"
 }
],


"route":{

 "auto_detect_interface":true,

 "default_domain_resolver":"dns-node",

 "rules":[

  {
   "protocol":"dns",
   "outbound":"proxy"
  },


  {
   "port":$SSH_PORT,
   "outbound":"direct"
  },


  {
   "ip_is_private":true,
   "outbound":"direct"
  }

 ],

 "final":"proxy"
}

}
EOF


echo
echo "配置生成完成"
echo


# ----------------------------------------------------------
# check config
# ----------------------------------------------------------

echo "检查 sing-box 配置"

if ! "$BIN" check -c "$CONFIG"
then

    echo
    echo "配置错误"
    exit 1

fi


echo
echo "配置正常"
echo


# ----------------------------------------------------------
# start sing-box
# ----------------------------------------------------------

echo "启动 TUN..."

"$BIN" run -c "$CONFIG" \
    >/dev/null 2>&1 &


SB_PID=$!


sleep 5


if ! kill -0 "$SB_PID" >/dev/null 2>&1
then

    echo
    echo "sing-box启动失败"
    exit 1

fi


# ----------------------------------------------------------
# connectivity test
# ----------------------------------------------------------

echo
echo "检测节点连通性..."

TEST_OK=0


for i in 1 2 3
do

    if curl \
       --connect-timeout 5 \
       --max-time 8 \
       -I https://www.cloudflare.com \
       >/dev/null 2>&1

    then

        TEST_OK=1
        break

    fi


    sleep 2

done



if [ "$TEST_OK" = "1" ]
then

    echo
    echo "================================"
    echo " 节点连接成功"
    echo " sing-box运行中"
    echo
    echo "PID:"
    echo "$SB_PID"
    echo
    echo "配置:"
    echo "$CONFIG"
    echo "================================"


else


    echo
    echo "节点连接失败"
    echo "恢复网络..."


    kill "$SB_PID" >/dev/null 2>&1 || true


    ip link delete singtun \
        >/dev/null 2>&1 || true


    exit 1

fi


wait "$SB_PID"
