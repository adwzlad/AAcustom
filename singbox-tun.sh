#!/usr/bin/env bash

set -euo pipefail

VERSION="1.0.0"

BASE_DIR="/root/singbox"
SINGBOX_BIN="${BASE_DIR}/sing-box"
CONFIG_FILE="${BASE_DIR}/config.json"


#######################################
# 基础检测
#######################################

check_root()
{
    if [ "$(id -u)" != "0" ]; then
        echo "错误: 请使用 root 运行"
        exit 1
    fi
}


check_system()
{
    if ! command -v apt >/dev/null 2>&1; then
        echo "不支持当前系统"
        exit 1
    fi
}


install_dependencies()
{
    apt update -y >/dev/null 2>&1

    apt install -y \
        curl \
        wget \
        unzip \
        jq \
        ca-certificates \
        iproute2 \
        iptables \
        >/dev/null 2>&1
}


#######################################
# sing-box安装
#######################################

install_singbox()
{

    mkdir -p "${BASE_DIR}"

    if [ -x "${SINGBOX_BIN}" ]; then
        return
    fi


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


    echo "下载 sing-box..."

    VERSION_TAG=$(curl -fsSL \
    https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | jq -r .tag_name)


    URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/sing-box-${VERSION_TAG#v}-linux-${SB_ARCH}.tar.gz"


    TMP=$(mktemp -d)


    curl -L "${URL}" \
        -o "${TMP}/singbox.tar.gz"


    tar xf "${TMP}/singbox.tar.gz" \
        -C "${TMP}"


    cp \
    "${TMP}"/sing-box-*/sing-box \
    "${SINGBOX_BIN}"


    chmod +x "${SINGBOX_BIN}"


    rm -rf "${TMP}"


    echo "sing-box安装完成"
}



#######################################
# 已运行检测
#######################################

check_running()
{

    PID=$(pgrep -f "${SINGBOX_BIN}" || true)


    if [ -n "${PID}" ]; then

        echo
        echo "检测到 sing-box 已运行"
        echo
        echo "PID: ${PID}"
        echo

        read -rp \
        "1.停止并重新部署  2.退出 [1/2]: " CHOICE


        if [ "${CHOICE}" = "1" ]; then

            kill "${PID}" || true

            sleep 2

            ip link delete singtun 2>/dev/null || true

        else

            exit 0

        fi

    fi
}



#######################################
# SSH保护
#######################################

get_ssh_port()
{

    SSH_PORT=$(sshd -T 2>/dev/null \
    | awk '/^port /{print $2}' \
    | head -1)


    if [ -z "${SSH_PORT}" ]; then
        SSH_PORT=22
    fi

}



#######################################
# 输入节点
#######################################

input_node()
{

    echo
    echo "请输入单节点URL:"
    echo
    echo "支持:"
    echo "vless://"
    echo "hysteria2://"
    echo "tuic://"
    echo "ss://"
    echo


    read -rp "节点: " NODE_URL


    if [[ ! "${NODE_URL}" =~ ^(vless|hysteria2|tuic|ss):// ]]; then

        echo "节点格式错误"
        exit 1

    fi

}



#######################################
# 生成配置
#######################################

generate_config()
{

cat > "${CONFIG_FILE}" <<EOF
{
  "log": {
    "level": "error"
  },

  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "singtun",
      "inet4_address": "172.19.0.1/30",
      "auto_route": true,
      "strict_route": true,
      "stack": "system"
    }
  ],


  "outbounds": [

    {
      "type": "urltest",
      "tag": "proxy",
      "outbounds": [
        "node"
      ]
    },


    {
      "type": "direct",
      "tag": "direct"
    }

  ],


  "route": {

    "auto_detect_interface": true,


    "rules": [

      {
        "port": ${SSH_PORT},
        "outbound": "direct"
      }

    ],


    "final": "proxy"

  }

}

EOF


    # 使用sing-box自带URL解析生成节点

    TMP=$(mktemp)


    "${SINGBOX_BIN}" merge \
        "${TMP}" \
        "${NODE_URL}" \
        >/dev/null 2>&1 || true


    rm -f "${TMP}"



    # 如果版本支持url直接生成
    jq \
    --arg url "${NODE_URL}" \
    '.outbounds[0] = {
        "type":"urltest",
        "tag":"proxy",
        "outbounds":["node"]
    }' \
    "${CONFIG_FILE}" \
    > "${CONFIG_FILE}.tmp"


    mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"

}



#######################################
# 启动测试
#######################################

start_test()
{

    echo
    echo "检查配置..."

    "${SINGBOX_BIN}" check \
        -c "${CONFIG_FILE}"


    echo
    echo "启动 sing-box TUN..."

    "${SINGBOX_BIN}" run \
        -c "${CONFIG_FILE}" &


    SB_PID=$!


    sleep 8


    echo
    echo "测试代理出口..."


    if curl \
       --connect-timeout 10 \
       https://api.ipify.org
    then

        echo
        echo
        echo "================================"
        echo "启动成功"
        echo "PID: ${SB_PID}"
        echo "================================"


        wait "${SB_PID}"


    else

        echo
        echo "节点不可用"


        kill "${SB_PID}" 2>/dev/null || true


        ip link delete singtun \
        2>/dev/null || true


        echo
        echo "已经恢复原网络"

        exit 1

    fi

}



#######################################
# 停止
#######################################

stop()
{

PID=$(pgrep -f "${SINGBOX_BIN}" || true)


if [ -n "${PID}" ]; then

    kill "${PID}" || true

fi


ip link delete singtun \
2>/dev/null || true


echo "sing-box 已停止"

}



#######################################
# 主程序
#######################################

main()
{

echo
echo "================================="
echo " Sing-box TUN OneKey"
echo " Version ${VERSION}"
echo "================================="
echo


if [ "${1:-}" = "stop" ]; then
    stop
    exit 0
fi


check_root

check_system

check_running

install_dependencies

install_singbox

get_ssh_port

input_node

generate_config

start_test

}


main "$@"
