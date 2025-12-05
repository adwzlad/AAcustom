#!/bin/bash
# nftables.sh - 自动管理 nftables 防火墙与端口重定向（Debian 12+）

WORK_DIR="/root/nftables"
PROT_FILE="$WORK_DIR/prot"
NFT_FILE="$WORK_DIR/nftables.conf"
LAST_MOD_FILE="$WORK_DIR/.prot_last_mod"

mkdir -p "$WORK_DIR"

check_root() {
    [ "$EUID" -ne 0 ] && { echo "❌ 请用 root 权限运行"; exit 1; }
}

init_prot_file() {
    if [ ! -f "$PROT_FILE" ]; then
        echo "⚠️ 首次运行，生成示例 prot 文件: $PROT_FILE"
        cat > "$PROT_FILE" <<EOF
# tcp:端口列表
# udp:端口列表
# icmp
tcp:80,443
udp:53
icmp

# forward:协议:起始端口-结束端口:目标端口
forward:udp:50000-60000:63448
EOF
        echo "✅ 已生成 prot 文件，请编辑后再次运行脚本"
        exit 0
    fi
}

get_last_mod() {
    [ ! -f "$LAST_MOD_FILE" ] && echo 0 > "$LAST_MOD_FILE"
    cat "$LAST_MOD_FILE"
}

update_last_mod() {
    stat -c %Y "$PROT_FILE" > "$LAST_MOD_FILE"
}

prot_modified() {
    last=$(get_last_mod)
    current=$(stat -c %Y "$PROT_FILE")
    [ "$current" -gt "$last" ] && return 0 || return 1
}

detect_iface() {
    IFACE=$(ip route | awk '/default/ {print $5; exit}')
    [ -z "$IFACE" ] && IFACE="eth0"
    echo "🌐 检测到主网卡: $IFACE"
}

get_ssh_port() {
    SSH_PORT=$(grep -i "^Port " /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
    [ -z "$SSH_PORT" ] && SSH_PORT=$(ss -tnlp | grep -i sshd | awk '{print $4}' | sed 's/.*://g' | sort -u | head -n1)
    [ -z "$SSH_PORT" ] && SSH_PORT=22
    echo "🔑 检测到 SSH 端口: $SSH_PORT"
}

merge_ports() {
    ports=($(printf "%s\n" "$@" | sort -n))
    result=""
    start=""
    prev=""
    for p in "${ports[@]}"; do
        if [ -z "$start" ]; then
            start=$p
            prev=$p
            continue
        fi
        if [ $((prev + 1)) -eq $p ]; then
            prev=$p
        else
            if [ "$start" -eq "$prev" ]; then
                result+="$start "
            else
                result+="$start-$prev "
            fi
            start=$p
            prev=$p
        fi
    done
    if [ -n "$start" ]; then
        if [ "$start" -eq "$prev" ]; then
            result+="$start"
        else
            result+="$start-$prev"
        fi
    fi
    echo "$result"
}

apply_nftables() {
    echo "生成 nftables 配置文件: $NFT_FILE"

    echo "flush ruleset" > "$NFT_FILE"
    echo "table inet filter {" >> "$NFT_FILE"
    echo "    chain input {" >> "$NFT_FILE"
    echo "        type filter hook input priority 0;" >> "$NFT_FILE"
    echo "        policy drop;" >> "$NFT_FILE"
    echo "        iif lo accept" >> "$NFT_FILE"
    echo "        ct state established,related accept" >> "$NFT_FILE"
    echo "        tcp dport $SSH_PORT accept" >> "$NFT_FILE"

    TCP_PORTS=($SSH_PORT)
    UDP_PORTS=()

    while read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        proto=$(echo "$line" | cut -d: -f1)
        ports=$(echo "$line" | cut -d: -f2- | tr -d ' ')
        case "$proto" in
            tcp)
                for p in $(echo "$ports" | tr ',' ' '); do
                    [[ "$p" == "$SSH_PORT" ]] && continue
                    echo "        tcp dport $p accept" >> "$NFT_FILE"
                    TCP_PORTS+=($p)
                done
                ;;
            udp)
                for p in $(echo "$ports" | tr ',' ' '); do
                    if [[ $p =~ - ]]; then
                        echo "        udp dport $p accept" >> "$NFT_FILE"
                        # 自动展开放行端口段
                        start=$(echo $p | cut -d- -f1)
                        end=$(echo $p | cut -d- -f2)
                        for ((i=start;i<=end;i++)); do UDP_PORTS+=($i); done
                    else
                        echo "        udp dport $p accept" >> "$NFT_FILE"
                        UDP_PORTS+=($p)
                    fi
                done
                ;;
            icmp)
                echo "        icmp type echo-request accept" >> "$NFT_FILE"
                ;;
        esac
    done < "$PROT_FILE"

    echo "    }" >> "$NFT_FILE"
    echo "}" >> "$NFT_FILE"

    # 端口重定向，仅本机内部
    FORWARD_PORTS=()
    while read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        [[ "$line" =~ ^forward: ]] || continue
        proto=$(echo "$line" | cut -d: -f2)
        src=$(echo "$line" | cut -d: -f3)
        dst=$(echo "$line" | cut -d: -f4)
        echo "添加内部端口重定向: $proto $src -> $dst"
        echo "table inet nat {" >> "$NFT_FILE"
        echo "    chain prerouting {" >> "$NFT_FILE"
        echo "        type nat hook prerouting priority 0;" >> "$NFT_FILE"
        echo "        iif $IFACE $proto dport $src redirect to :$dst" >> "$NFT_FILE"
        echo "    }" >> "$NFT_FILE"
        echo "}" >> "$NFT_FILE"
        FORWARD_PORTS+=("$proto:$src:$dst")
        # 自动把 src 和 dst 加入放行
        if [[ "$proto" == "udp" ]]; then
            if [[ $src =~ - ]]; then
                start=$(echo $src | cut -d- -f1)
                end=$(echo $src | cut -d- -f2)
                for ((i=start;i<=end;i++)); do UDP_PORTS+=($i); done
            else
                UDP_PORTS+=($src)
            fi
            UDP_PORTS+=($dst)
        elif [[ "$proto" == "tcp" ]]; then
            TCP_PORTS+=($src)
            TCP_PORTS+=($dst)
        fi
    done < "$PROT_FILE"

    nft -f "$NFT_FILE"
    nft list ruleset > /etc/nftables.conf
    systemctl enable nftables --now
}

show_summary() {
    echo "===== nftables 防火墙概览 ====="
    echo "🌐 主网卡: $IFACE"
    echo "🔑 SSH端口放行: $SSH_PORT"
    echo "💻 TCP 放行端口: $(merge_ports "${TCP_PORTS[@]}")"
    echo "📡 UDP 放行端口: $(merge_ports "${UDP_PORTS[@]}")"
    grep -q '^icmp' "$PROT_FILE" && echo "📢 ICMP: 放行" || echo "📢 ICMP: 阻止"
    echo "⚡ 内部端口重定向:"
    for f in "${FORWARD_PORTS[@]}"; do
        proto=$(echo $f | cut -d: -f1 | tr '[:lower:]' '[:upper:]')
        src=$(echo $f | cut -d: -f2)
        dst=$(echo $f | cut -d: -f3)
        echo "  $proto $src -> $dst"
    done
    echo "=============================="
}

### 主流程 ###
check_root
init_prot_file
detect_iface
get_ssh_port

if prot_modified; then
    apply_nftables
    update_last_mod
    show_summary
    echo "✅ nftables 规则已应用并持久化。"
else
    show_summary
    echo "ℹ️ prot 文件未修改，规则保持不变。"
fi
