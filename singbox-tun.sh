#!/usr/bin/env bash
#
# Sing-box TUN OneKey
# Temporary transparent proxy
#
# Support:
# Ubuntu 22.04/24.04
# Debian 11/12/13
#
# Runtime:
# /root/singbox
#

set -euo pipefail

VERSION="2.0.0"

BASE_DIR="/root/singbox"
BIN="${BASE_DIR}/sing-box"
CONFIG="${BASE_DIR}/config.json"


#####################################
# root check
#####################################

if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 运行"
    exit 1
fi


mkdir -p "${BASE_DIR}"


#####################################
# stop
#####################################

stop_box()
{
    echo "停止 sing-box..."

    pkill -f "${BIN}" 2>/dev/null || true

    ip link delete singtun 2>/dev/null || true

    echo "完成"
}


if [ "${1:-}" = "stop" ]; then
    stop_box
    exit 0
fi


#####################################
# running check
#####################################

check_running()
{

    PID=$(pgrep -f "${BIN}" || true)

    if [ -n "${PID}" ]; then

        echo
        echo "发现 sing-box 已运行"
        echo "PID: ${PID}"
        echo

        read -rp "停止旧实例重新运行? [y/N]: " c

        if [ "${c}" = "y" ]; then
            stop_box
            sleep 2
        else
            exit 0
        fi

    fi

}



#####################################
# dependency
#####################################

install_dep()
{

    export DEBIAN_FRONTEND=noninteractive

    apt update -y >/dev/null 2>&1

    apt install -y \
        curl \
        jq \
        unzip \
        python3 \
        iproute2 \
        >/dev/null 2>&1

}



#####################################
# install sing-box
#####################################

install_singbox()
{

    if [ -x "${BIN}" ]; then
        return
    fi


    echo "下载 sing-box..."


    ARCH=$(uname -m)


    case "${ARCH}" in

        x86_64)
            SB_ARCH="amd64"
            ;;

        aarch64|arm64)
            SB_ARCH="arm64"
            ;;

        *)
            echo "不支持架构 ${ARCH}"
            exit 1
            ;;

    esac



    TAG=$(curl -fsSL \
    https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | jq -r '.tag_name')



    TMP=$(mktemp -d)



    URL="https://github.com/SagerNet/sing-box/releases/download/${TAG}/sing-box-${TAG#v}-linux-${SB_ARCH}.tar.gz"


    curl -L "${URL}" \
        -o "${TMP}/singbox.tar.gz"



    tar xf "${TMP}/singbox.tar.gz" \
        -C "${TMP}"


    cp \
    "${TMP}"/sing-box-*/sing-box \
    "${BIN}"


    chmod +x "${BIN}"


    rm -rf "${TMP}"


    echo "sing-box安装完成"

}



#####################################
# ssh port
#####################################

get_ssh_port()
{

    SSH_PORT=$(sshd -T 2>/dev/null \
    | awk '/^port /{print $2}' \
    | head -1)



    if [ -z "${SSH_PORT}" ]; then
        SSH_PORT=22
    fi


    echo "SSH保护端口: ${SSH_PORT}"

}



#####################################
# input node
#####################################

input_node()
{

echo
echo "================================="
echo "请输入节点URL"
echo
echo "支持:"
echo "vless://"
echo "hysteria2://"
echo "tuic://"
echo "anytls://"
echo "ss://"
echo "================================="
echo


read -rp "节点: " NODE_URL



case "${NODE_URL}" in

    vless://*)
        TYPE="vless"
        ;;

    hysteria2://*)
        TYPE="hysteria2"
        ;;

    tuic://*)
        TYPE="tuic"
        ;;

    anytls://*)
        TYPE="anytls"
        ;;

    ss://*)
        TYPE="ss"
        ;;

    *)
        echo "不支持节点类型"
        exit 1
        ;;

esac


}


#####################################
# parse node
#####################################

parse_node()
{

python3 <<PY

import urllib.parse,json,sys

url='''${NODE_URL}'''

u=urllib.parse.urlparse(url)

q=urllib.parse.parse_qs(u.query)


node={}


# server

node["server"]=u.hostname

node["server_port"]=u.port


PY

}


#####################################
# generate config
#####################################

generate_config()
{

python3 - "${NODE_URL}" "${CONFIG}" "${SSH_PORT}" <<'PY'

import sys
import json
import urllib.parse
import base64


url=sys.argv[1]
cfgfile=sys.argv[2]
sshport=int(sys.argv[3])


u=urllib.parse.urlparse(url)

q=urllib.parse.parse_qs(u.query)


node={}

tag="proxy"



#################################
# VLESS
#################################

if u.scheme=="vless":

    node={
        "type":"vless",
        "tag":tag,
        "server":u.hostname,
        "server_port":u.port,
        "uuid":u.username
    }


    tls={}

    if q.get("security",[""])[0]=="reality":

        tls={
            "enabled":True,
            "server_name":q.get("sni",[""])[0],
            "reality":{
                "enabled":True,
                "public_key":q.get("pbk",[""])[0],
                "short_id":q.get("sid",[""])[0]
            }
        }


    elif q.get("security",[""])[0]=="tls":

        tls={
            "enabled":True,
            "server_name":q.get("sni",[""])[0]
        }


    if tls:
        node["tls"]=tls



#################################
# AnyTLS
#################################

elif u.scheme=="anytls":

    node={
        "type":"anytls",
        "tag":tag,
        "server":u.hostname,
        "server_port":u.port,
        "password":urllib.parse.unquote(u.username),
        "tls":{
            "enabled":True
        }
    }


    if "sni" in q:
        node["tls"]["server_name"]=q["sni"][0]


    if "insecure" in q:
        node["tls"]["insecure"]=True



#################################
# TUIC
#################################

elif u.scheme=="tuic":

    node={
        "type":"tuic",
        "tag":tag,
        "server":u.hostname,
        "server_port":u.port,
        "uuid":u.username,
        "password":u.password,
        "congestion_control":
            q.get("congestion_control",["bbr"])[0],
        "tls":{
            "enabled":True
        }
    }


    if "sni" in q:
        node["tls"]["server_name"]=q["sni"][0]


    if "alpn" in q:
        node["tls"]["alpn"]=q["alpn"][0].split(",")



#################################
# Hysteria2
#################################

elif u.scheme=="hysteria2":

    node={
        "type":"hysteria2",
        "tag":tag,
        "server":u.hostname,
        "server_port":u.port,
        "password":urllib.parse.unquote(u.username),
        "tls":{
            "enabled":True
        }
    }


    if "sni" in q:
        node["tls"]["server_name"]=q["sni"][0]


    if "insecure" in q:
        node["tls"]["insecure"]=True



#################################
# Shadowsocks
#################################

elif u.scheme=="ss":

    raw=url.split("ss://")[1].split("#")[0]


    try:
        data=base64.urlsafe_b64decode(
            raw+"=="
        ).decode()

    except:
        data=urllib.parse.unquote(raw)


    method,password,server=data.split("@")[0].split(":")+data.split("@")[1].split(":")[0:0]


else:

    raise Exception("unsupported")



config={

"log":{
    "level":"error"
},


"dns":{
    "servers":[
        {
            "tag":"dns",
            "address":"https://1.1.1.1/dns-query"
        }
    ]
},


"inbounds":[
    {
        "type":"tun",
        "tag":"tun-in",
        "interface_name":"singtun",
        "inet4_address":"172.19.0.1/30",
        "auto_route":True,
        "strict_route":True,
        "stack":"system"
    }
],


"outbounds":[

    node,

    {
        "type":"direct",
        "tag":"direct"
    }

],



"route":{

    "auto_detect_interface":True,


    "rules":[

        {
            "port":sshport,
            "outbound":"direct"
        }

    ],


    "final":"proxy"

}

}



with open(cfgfile,"w") as f:

    json.dump(
        config,
        f,
        indent=2
    )

PY


echo
echo "配置生成完成:"
echo "${CONFIG}"

}



#####################################
# check config
#####################################

check_config()
{

echo
echo "检查 sing-box 配置..."

"${BIN}" check \
-c "${CONFIG}"


}



#####################################
# start
#####################################

start_box()
{

echo
echo "启动 TUN..."


"${BIN}" run \
-c "${CONFIG}" &


PID=$!


sleep 8


echo
echo "检测出口..."


IP=$(curl -4 \
--connect-timeout 10 \
-s https://api.ipify.org || true)



if [ -n "${IP}" ]; then

    echo
    echo "================================"
    echo "启动成功"
    echo "出口IP:"
    echo "${IP}"
    echo "PID:"
    echo "${PID}"
    echo "================================"


    wait "${PID}"


else


    echo
    echo "节点连接失败"


    kill "${PID}" 2>/dev/null || true


    ip link delete singtun \
    2>/dev/null || true


    echo
    echo "已恢复原网络"


    exit 1

fi


}

#####################################
# main
#####################################

main()
{

echo
echo "================================="
echo " Sing-box TUN OneKey"
echo " Version ${VERSION}"
echo "================================="
echo


check_running


install_dep


install_singbox


get_ssh_port


input_node


generate_config


check_config


start_box


}


main "$@"
