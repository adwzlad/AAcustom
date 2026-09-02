#!/bin/bash
set -e

VERSION="1.6"

BASE="/root/singbox"
BIN="${BASE}/sing-box"
CFG="${BASE}/config.json"

mkdir -p "${BASE}"

echo
echo "================================"
echo " Sing-box TUN ${VERSION}"
echo " DNS node resolve : 1.1.1.1"
echo " Client DNS proxy : 223.5.5.5"
echo " SSH bypass       : 22"
echo " Temporary mode"
echo "================================"
echo


# ==============================
# root检查
# ==============================

if [ "$(id -u)" != "0" ]; then
    echo "请使用root运行"
    exit 1
fi



# ==============================
# 清理旧运行
# ==============================

if pgrep -f "${BASE}/sing-box run" >/dev/null 2>&1; then

    echo "检测到已有 sing-box 运行"

    pkill -f "${BASE}/sing-box run" || true

    sleep 2

fi



# ==============================
# SSH端口检测
# ==============================

SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)

if [ -z "${SSH_PORT}" ]; then
    SSH_PORT=22
fi


echo
echo "SSH保护端口: ${SSH_PORT}"
echo



# ==============================
# 下载 sing-box
# ==============================


install_singbox()
{

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



if [ ! -f "${BIN}" ]; then


    echo "下载 sing-box..."


    TMP="/tmp/sing-box.tar.gz"


    URL="https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-${SB_ARCH}-linux.tar.gz"



    curl -L "${URL}" -o "${TMP}"



    tar -xzf "${TMP}" -C /tmp



    FILE=$(find /tmp -type f -name sing-box | head -1)



    cp "${FILE}" "${BIN}"


    chmod +x "${BIN}"



    rm -rf /tmp/sing-box*



    echo "sing-box安装完成"


fi


}



install_singbox



# ==============================
# 输入节点
# ==============================


echo
read -r -p "请输入 anytls/tuic 节点URL: " NODE_URL



if [[ "${NODE_URL}" != anytls://* ]] && [[ "${NODE_URL}" != tuic://* ]]; then

    echo
    echo "只支持 anytls:// 和 tuic://"
    exit 1

fi



# 保存原始URL

echo "${NODE_URL}" > "${BASE}/node.url"



echo
echo "解析节点..."

# ==============================
# URL解析
# ==============================


python3 <<'PY'
import urllib.parse
import json
import sys
import os


url=open("/root/singbox/node.url").read().strip()


u=urllib.parse.urlparse(url)


data={}

data["scheme"]=u.scheme
data["host"]=u.hostname
data["port"]=u.port


if u.username:
    data["username"]=urllib.parse.unquote(u.username)


if u.password:
    data["password"]=urllib.parse.unquote(u.password)


q=urllib.parse.parse_qs(u.query)


for k,v in q.items():
    data[k]=v[0]


data["name"]=urllib.parse.unquote(u.fragment)


with open("/root/singbox/node.json","w") as f:
    json.dump(data,f,indent=2)


PY



NODE_TYPE=$(python3 - <<'PY'
import json
print(json.load(open('/root/singbox/node.json'))["scheme"])
PY
)


SERVER=$(python3 - <<'PY'
import json
print(json.load(open('/root/singbox/node.json'))["host"])
PY
)


PORT=$(python3 - <<'PY'
import json
print(json.load(open('/root/singbox/node.json'))["port"])
PY
)



echo

echo "节点类型: ${NODE_TYPE}"

echo "服务器: ${SERVER}"

echo "端口: ${PORT}"

echo



# ==============================
# 生成sing-box配置
# ==============================


python3 <<PY
import json


node=json.load(open("${BASE}/node.json"))


scheme=node["scheme"]


outbound={

    "type":scheme,

    "tag":"proxy",

    "server":node["host"],

    "server_port":node["port"],

    "domain_resolver":"node-resolve"

}



if scheme=="anytls":

    outbound["password"]=node.get("username","")

    
    outbound["tls"]={

        "enabled":True,

        "insecure": node.get("insecure","0")=="1"

    }



    if "sni" in node:
        outbound["tls"]["server_name"]=node["sni"]



    if "fp" in node:
        outbound["tls"]["utls"]={

            "enabled":True,

            "fingerprint":node["fp"]

        }




elif scheme=="tuic":


    outbound["uuid"]=node.get("username","")

    outbound["password"]=node.get("password","")



    outbound["congestion_control"]=node.get(

        "congestion_control",

        "bbr"

    )


    outbound["tls"]={

        "enabled":True,

        "insecure":node.get("insecure","0")=="1"

    }



    if "sni" in node:

        outbound["tls"]["server_name"]=node["sni"]





config={


"inbounds":[

{

"type":"tun",

"tag":"tun-in",

"interface_name":"singtun",

"inet4_address":"172.19.0.1/30",

"auto_route":True,

"strict_route":True,

"sniff":True

}

],



"outbounds":[


outbound,


{

"type":"direct",

"tag":"direct"

},


{

"type":"block",

"tag":"block"

}


],





"dns":{


"servers":[


{

"tag":"node-resolve",

"type":"https",

"server":"1.1.1.1",

"domain_resolver":"",

"detour":"direct"

},


{

"tag":"proxy-dns",

"type":"udp",

"server":"223.5.5.5",

"detour":"proxy"

}


],



"rules":[


{

"server":"proxy-dns",

"clash_mode":"Global"

}


]


},





"route":{


"default_domain_resolver":"node-resolve",


"auto_detect_interface":True,


"rules":[


{

"inbound":[

"tun-in"

],

"port":int("${SSH_PORT}"),

"outbound":"direct"

}


]

}



}



json.dump(

config,

open("${CFG}","w"),

indent=2

)


PY



echo

echo "配置生成完成"

echo

echo "检查 sing-box 配置"

"${BIN}" check -c "${CFG}"

echo

echo "配置正常"

echo

# ==============================
# 启动 TUN
# ==============================


echo
echo "启动 TUN..."



"${BIN}" run -c "${CFG}" >/dev/null 2>&1 &


SB_PID=$!



sleep 8



# ==============================
# 检查进程
# ==============================


if ! kill -0 "${SB_PID}" 2>/dev/null; then


    echo
    echo "sing-box启动失败"
    exit 1


fi



# ==============================
# 节点连通检测
# ==============================


echo

echo "检测节点连通性..."



TEST_IP=$(curl \
--connect-timeout 15 \
--max-time 20 \
-4 \
-s \
https://api.ipify.org || true)



if [ -z "${TEST_IP}" ]; then


    echo

    echo "================================"

    echo "节点连接失败"

    echo "正在恢复网络..."

    echo "================================"


    kill "${SB_PID}" 2>/dev/null || true


    sleep 2


    ip link delete singtun 2>/dev/null || true


    exit 1


fi





echo

echo "================================"

echo " Sing-box TUN运行成功"

echo "================================"

echo

echo "出口IP: ${TEST_IP}"

echo "进程PID: ${SB_PID}"

echo

echo "配置文件:"
echo "${CFG}"

echo

echo "规则:"

echo " SSH ${SSH_PORT} -> direct"

echo " 其它IPv4流量 -> TUN"

echo " 节点解析DNS -> 1.1.1.1"

echo "客户端DNS -> 223.5.5.5(proxy)"

echo

echo "临时模式:"

echo "重启后自动失效"

echo





# ==============================
# 保持运行
# ==============================


wait "${SB_PID}"
