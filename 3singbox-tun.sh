#!/usr/bin/env bash

set -euo pipefail

VERSION="1.4"

BASE="/root/singbox"

BIN="${BASE}/sing-box"

CFG="${BASE}/config.json"


mkdir -p "${BASE}"


echo
echo "================================"
echo " Sing-box TUN ${VERSION}"
echo " DNS: 1.1.1.1 DoH"
echo " SSH bypass: 22"
echo " Temporary mode"
echo "================================"
echo



if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 运行"
    exit 1
fi



if [ ! -c /dev/net/tun ]; then

    echo "错误: 系统没有 TUN 支持"

    exit 1

fi



# ================================
# 检查已有 sing-box
# ================================


if pgrep -f "${BIN}" >/dev/null 2>&1; then

    echo

    echo "检测到已有 sing-box 运行"

    read -rp "是否停止旧进程? [y/N]: " answer


    if [[ "${answer}" != "y" ]]; then

        exit 0

    fi


    pkill -f "${BIN}" || true

    sleep 2

fi




# ================================
# 基础依赖
# ================================


apt update -y >/dev/null 2>&1 || true


apt install -y \
curl \
jq \
python3 \
ca-certificates \
iproute2 \
>/dev/null 2>&1




# ================================
# 下载 sing-box
# ================================


if [ ! -x "${BIN}" ]; then


echo

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



echo "sing-box安装完成"


fi




# ================================
# SSH端口
# ================================


SSH_PORT=$(sshd -T 2>/dev/null \
| awk '/^port /{print $2}' \
| head -1)



[ -z "${SSH_PORT}" ] && SSH_PORT=22



echo

echo "SSH保护端口: ${SSH_PORT}"

echo



# ================================
# 输入节点
# ================================


read -rp "请输入 anytls/tuic 节点URL: " NODE



case "${NODE}" in


anytls://*)

    NODE_TYPE="anytls"

    ;;


tuic://*)

    NODE_TYPE="tuic"

    ;;


*)

    echo

    echo "只支持 anytls:// 和 tuic://"

    exit 1

    ;;


esac

# ================================
# 生成 sing-box 配置
# ================================


python3 - "${NODE}" "${CFG}" "${SSH_PORT}" <<'PY'


import sys
import json
import urllib.parse



url=sys.argv[1]

cfg=sys.argv[2]

ssh_port=int(sys.argv[3])



u=urllib.parse.urlparse(url)

q=urllib.parse.parse_qs(u.query)



# ================================
# anytls
# ================================


if u.scheme=="anytls":



    outbound={


        "type":"anytls",


        "tag":"proxy",


        "server":u.hostname,


        "server_port":u.port,


        "password":urllib.parse.unquote(
            u.username or ""
        ),



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




# ================================
# tuic
# ================================


elif u.scheme=="tuic":



    outbound={


        "type":"tuic",


        "tag":"proxy",


        "server":u.hostname,


        "server_port":u.port,


        "uuid":urllib.parse.unquote(
            u.username or ""
        ),



        "password":urllib.parse.unquote(
            u.password or ""
        ),



        "congestion_control":
            q.get(
                "congestion_control",
                ["bbr"]
            )[0],



        "tls":{


            "enabled":True


        }


    }





    if "sni" in q:


        outbound["tls"]["server_name"]=q["sni"][0]



    if "insecure" in q:


        outbound["tls"]["insecure"]=True



    if "alpn" in q:


        outbound["tls"]["alpn"]=q["alpn"][0].split(",")



else:


    raise Exception(
        "unsupported protocol"
    )





config={



"log":{


    "level":"error"


},





"dns":{


    "servers":[



        {


            "type":"https",


            "tag":"dns-1",


            "server":"1.1.1.1",


            "path":"/dns-query",


            "detour":"proxy"


        }


    ],



    "final":"dns-1"


},





"inbounds":[



    {


        "type":"tun",


        "tag":"tun-in",


        "interface_name":"singtun",



        "address":[


            "172.19.0.1/30",


            "fdfe:dcba::1/126"


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


            "protocol":"dns",


            "action":"hijack-dns"


        },




        {


            "port":ssh_port,


            "outbound":"direct"


        }





    ],




    "final":"proxy"



}



}




with open(cfg,"w") as f:


    json.dump(
        config,
        f,
        indent=2
    )



PY




echo

echo "配置生成完成"

echo



# 检查配置

echo "检查 sing-box 配置"


"${BIN}" check -c "${CFG}"



echo

echo "配置正常"

echo

# ================================
# 启动 sing-box
# ================================


echo

echo "启动 TUN..."



"${BIN}" run -c "${CFG}" &


SB_PID=$!



sleep 8




# ================================
# 检查进程
# ================================


if ! kill -0 "${SB_PID}" 2>/dev/null; then


    echo

    echo "sing-box启动失败"

    exit 1


fi




echo

echo "检测节点连通性..."




# ================================
# 测试出口
# ================================


CHECK_IP=$(curl \
-4 \
--connect-timeout 15 \
-s \
https://api.ipify.org || true)




if [ -z "${CHECK_IP}" ]; then



    echo

    echo "节点连接失败"

    echo "正在恢复网络..."



    kill "${SB_PID}" 2>/dev/null || true



    sleep 2



    ip link delete singtun 2>/dev/null || true



    exit 1



fi





echo

echo "================================"

echo " Sing-box TUN运行成功"

echo " 出口IP: ${CHECK_IP}"

echo " PID: ${SB_PID}"

echo " 配置: ${CFG}"

echo "================================"

echo



# 保持运行

wait "${SB_PID}"

