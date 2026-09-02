#!/usr/bin/env bash

set -euo pipefail

VERSION="1.3"

BASE="/root/singbox"
BIN="${BASE}/sing-box"
CFG="${BASE}/config.json"

mkdir -p "${BASE}"


echo
echo "================================"
echo " Sing-box TUN ${VERSION}"
echo " DNS: 1.1.1.1 DoH"
echo " SSH bypass: 22"
echo "================================"
echo


if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 运行"
    exit 1
fi


if [ ! -c /dev/net/tun ]; then
    echo "系统没有 TUN 支持 (/dev/net/tun)"
    exit 1
fi


# 停止旧实例
if pgrep -f "${BIN}" >/dev/null 2>&1; then

    echo "发现已有 sing-box 运行"

    read -rp "停止旧实例继续? [y/N]: " yn

    if [[ "${yn}" != "y" ]]; then
        exit 0
    fi

    pkill -f "${BIN}" || true

    sleep 2

fi



apt update -y >/dev/null 2>&1 || true

apt install -y \
curl \
jq \
python3 \
iproute2 \
ca-certificates \
>/dev/null 2>&1



# 下载 sing-box
if [ ! -x "${BIN}" ]; then


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
            echo "不支持架构: ${ARCH}"
            exit 1
            ;;

    esac


    TAG=$(curl -fsSL \
    https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | jq -r '.tag_name')


    TMP=$(mktemp -d)


    curl -L \
    "https://github.com/SagerNet/sing-box/releases/download/${TAG}/sing-box-${TAG#v}-linux-${SB_ARCH}.tar.gz" \
    -o "${TMP}/singbox.tar.gz"


    tar xf "${TMP}/singbox.tar.gz" -C "${TMP}"


    cp "${TMP}"/sing-box-*/sing-box "${BIN}"


    chmod +x "${BIN}"


    rm -rf "${TMP}"


fi



SSH_PORT=$(sshd -T 2>/dev/null \
| awk '/^port /{print $2}' \
| head -1)


[ -z "${SSH_PORT}" ] && SSH_PORT=22


echo
echo "SSH保护端口: ${SSH_PORT}"
echo



read -rp "请输入 anytls/tuic 节点URL: " NODE



case "${NODE}" in

    anytls://|anytls://*)
        TYPE="anytls"
        ;;

    tuic://|tuic://*)
        TYPE="tuic"
        ;;

    *)
        echo "只支持 anytls:// 和 tuic://"
        exit 1
        ;;

esac



python3 - "${NODE}" "${CFG}" "${SSH_PORT}" <<'PY'

import sys
import json
import urllib.parse


url=sys.argv[1]
cfg=sys.argv[2]
ssh=int(sys.argv[3])


u=urllib.parse.urlparse(url)

q=urllib.parse.parse_qs(u.query)



if u.scheme=="anytls":


    out={

        "type":"anytls",

        "tag":"proxy",

        "server":u.hostname,

        "server_port":u.port,

        "password":urllib.parse.unquote(u.username),

        "tls":{

            "enabled":True

        }

    }



    if "sni" in q:

        out["tls"]["server_name"]=q["sni"][0]



    if "insecure" in q:

        out["tls"]["insecure"]=True



    if "fp" in q:

        out["tls"]["utls"]={

            "enabled":True,

            "fingerprint":q["fp"][0]

        }



elif u.scheme=="tuic":


    out={

        "type":"tuic",

        "tag":"proxy",

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

        out["tls"]["server_name"]=q["sni"][0]



    if "alpn" in q:

        out["tls"]["alpn"]=q["alpn"][0].split(",")



else:

    raise Exception("unsupported")



config={


"log":{

    "level":"error"

},



"dns":{

    "servers":[

        {

        "tag":"cloudflare",

        "address":"https://1.1.1.1/dns-query",

        "detour":"proxy"

        }

    ],

    "final":"cloudflare"

},



"inbounds":[


{

"type":"tun",

"tag":"tun-in",

"interface_name":"singtun",

"address":[

    "172.19.0.1/30"

],

"auto_route":True,

"strict_route":True,

"stack":"system"

}


],



"outbounds":[


out,


{

"type":"direct",

"tag":"direct"

}


],



"route":{


"auto_detect_interface":True,


"rules":[


{

"type":"logical",

"mode":"or",

"rules":[

{

"port":ssh

}

],

"outbound":"direct"

},



{

"protocol":"dns",

"action":"hijack-dns"

}


],


"final":"proxy"


}


}



with open(cfg,"w") as f:

    json.dump(config,f,indent=2)


PY

echo

echo "检查 sing-box 配置"

"${BIN}" check -c "${CFG}"


echo

echo "启动 TUN"



"${BIN}" run -c "${CFG}" &

PID=$!



sleep 15



echo

echo "检测代理节点..."



# 检查进程

if ! kill -0 "${PID}" 2>/dev/null; then

    echo "sing-box启动失败"

    exit 1

fi



# 测试DNS

echo "测试 DNS..."



DNS_TEST=$(curl \
--interface singtun \
--connect-timeout 10 \
-s \
https://cloudflare-dns.com/dns-query \
-H 'accept: application/dns-json' \
-o /dev/null \
-w "%{http_code}" || true)



if [ "${DNS_TEST}" != "200" ]; then

    echo "DNS测试失败"

else

    echo "DNS正常"

fi




echo

echo "测试出口IP..."



IP=$(curl \
--interface singtun \
-4 \
--connect-timeout 15 \
-s \
https://api.ipify.org || true)




if [ -n "${IP}" ]; then


    echo

    echo "================================"

    echo " Sing-box TUN运行成功"

    echo " 出口IP: ${IP}"

    echo " PID: ${PID}"

    echo " 配置文件: ${CFG}"

    echo "================================"

    echo


    wait "${PID}"



else


    echo

    echo "================================"

    echo "节点连接失败"

    echo "停止 sing-box"

    echo "================================"


    kill "${PID}" 2>/dev/null || true


    ip link delete singtun 2>/dev/null || true


    exit 1


fi
