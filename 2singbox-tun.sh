#!/usr/bin/env bash

set -euo pipefail


VERSION="1.2"

BASE="/root/singbox"

BIN="${BASE}/sing-box"

CFG="${BASE}/config.json"



stop_box()
{
    pkill -f "${BIN}" 2>/dev/null || true

    ip link delete singtun 2>/dev/null || true

    echo "sing-box stopped"
}



if [ "${1:-}" = "stop" ]; then

    stop_box

    exit 0

fi



if [ "$(id -u)" != "0" ]; then

    echo "请使用 root 运行"

    exit 1

fi



mkdir -p "${BASE}"



if pgrep -f "${BIN}" >/dev/null; then

    echo "检测到 sing-box 正在运行"

    read -rp "停止旧实例? [y/N]: " c


    if [ "${c}" = "y" ]; then

        stop_box

        sleep 2

    else

        exit 0

    fi

fi



apt update -y >/dev/null 2>&1


apt install -y \
curl \
jq \
python3 \
iproute2 \
>/dev/null 2>&1




if [ ! -x "${BIN}" ]; then


    echo "下载 sing-box"


    ARCH=$(uname -m)


    case "${ARCH}" in

        x86_64)

            SB_ARCH="amd64"

            ;;


        aarch64|arm64|armv8l)

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



    curl -L \
    "https://github.com/SagerNet/sing-box/releases/download/${TAG}/sing-box-${TAG#v}-linux-${SB_ARCH}.tar.gz" \
    -o "${TMP}/singbox.tar.gz"



    tar xf "${TMP}/singbox.tar.gz" \
    -C "${TMP}"



    cp "${TMP}"/sing-box-*/sing-box "${BIN}"



    chmod +x "${BIN}"



    rm -rf "${TMP}"


fi




SSH_PORT=$(sshd -T 2>/dev/null \
| awk '/^port /{print $2}' \
| head -1)



[ -z "${SSH_PORT}" ] && SSH_PORT=22




echo

echo "================================"

echo " Sing-box TUN ${VERSION}"

echo " SSH保护端口: ${SSH_PORT}"

echo "================================"

echo



read -rp "请输入 anytls/tuic 节点URL: " NODE




case "${NODE}" in


anytls://*)

    ;;


tuic://*)

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


    outbound={

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

        outbound["tls"]["server_name"]=q["sni"][0]



    if "insecure" in q:

        outbound["tls"]["insecure"]=True



    if "fp" in q:

        outbound["tls"]["utls"]={

            "enabled":True,

            "fingerprint":q["fp"][0]

        }




elif u.scheme=="tuic":


    outbound={

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

        outbound["tls"]["server_name"]=q["sni"][0]



    if "alpn" in q:

        outbound["tls"]["alpn"]=q["alpn"][0].split(",")




else:

    raise Exception("unsupported")





config={


"log":{

    "level":"error"

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


outbound,


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

}


],



"final":"proxy"


}



}




with open(cfg,"w") as f:

    json.dump(config,f,indent=2)



PY




echo

echo "检查配置"


"${BIN}" check -c "${CFG}"




echo

echo "启动 TUN"



"${BIN}" run \
-c "${CFG}" &



PID=$!



sleep 8




echo

echo "检测节点"



IP=$(curl -4 \
--connect-timeout 10 \
-s https://api.ipify.org || true)




if [ -n "${IP}" ]; then


echo

echo "=============================="

echo "启动成功"

echo "出口IP: ${IP}"

echo "PID: ${PID}"

echo "=============================="



wait "${PID}"


else


echo

echo "节点连接失败，恢复网络"


kill "${PID}" 2>/dev/null || true


ip link delete singtun 2>/dev/null || true


exit 1


fi
