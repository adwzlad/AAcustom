#!/bin/bash
# firewall.sh - 全自动防火墙脚本（Debian 12）

WORK_DIR="/root/firewall"
PROT_FILE="$WORK_DIR/prot"
IPV4_RULES="$WORK_DIR/ipv4_rules.sh"
IPV6_RULES="$WORK_DIR/ipv6_rules.sh"
LAST_MOD_FILE="$WORK_DIR/.prot_last_mod"

check_root() {
    [ "$EUID" -ne 0 ] && { echo "❌ 请用 root 权限运行"; exit 1; }
}

mkdir -p "$WORK_DIR"

install_persistent() {
    echo "📦 安装 iptables-persistent..."
    apt update -y
    DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
    systemctl enable netfilter-persistent
    systemctl start netfilter-persistent
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
EOF
        echo "✅ 已生成 prot 文件，请编辑后再次运行脚本"
        exit 0
    fi
}

detect_stack() {
    IPV4=0; IPV6=0
    ip -4 addr show | grep -q "inet " && IPV4=1
    ip -6 addr show | grep -q "inet6 " && IPV6=1
}

get_ssh_port() {
    SSH_PORT=$(grep -i "^Port " /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
    [ -z "$SSH_PORT" ] && SSH_PORT=$(ss -tnlp | grep -i sshd | awk '{print $4}' | sed 's/.*://g' | sort -u | head -n1)
    [ -z "$SSH_PORT" ] && SSH_PORT=22
    echo "🔑 检测到 SSH 端口: $SSH_PORT"
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

generate_ipv4_rules() {
    echo "#!/bin/bash" > "$IPV4_RULES"
    echo "iptables -F" >> "$IPV4_RULES"
    echo "iptables -P INPUT DROP" >> "$IPV4_RULES"
    echo "iptables -P FORWARD DROP" >> "$IPV4_RULES"
    echo "iptables -P OUTPUT ACCEPT" >> "$IPV4_RULES"
    echo "iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT" >> "$IPV4_RULES"
    echo "iptables -A INPUT -i lo -j ACCEPT" >> "$IPV4_RULES"
    echo "iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT" >> "$IPV4_RULES"

    while read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        proto=$(echo "$line" | cut -d: -f1)
        ports=$(echo "$line" | cut -d: -f2- | tr -d ' ')
        case "$proto" in
            tcp)
                for port in $(echo "$ports" | tr ',' ' '); do
                    [[ "$port" == "$SSH_PORT" ]] && continue
                    echo "iptables -A INPUT -p tcp --dport $port -j ACCEPT" >> "$IPV4_RULES"
                done
                ;;
            udp)
                for port in $(echo "$ports" | tr ',' ' '); do
                    echo "iptables -A INPUT -p udp --dport $port -j ACCEPT" >> "$IPV4_RULES"
                done
                ;;
            icmp)
                echo "iptables -A INPUT -p icmp -j ACCEPT" >> "$IPV4_RULES"
                ;;
        esac
    done < "$PROT_FILE"

    chmod +x "$IPV4_RULES"
    "$IPV4_RULES"
}

generate_ipv6_rules() {
    echo "#!/bin/bash" > "$IPV6_RULES"
    echo "ip6tables -F" >> "$IPV6_RULES"
    echo "ip6tables -P INPUT DROP" >> "$IPV6_RULES"
    echo "ip6tables -P FORWARD DROP" >> "$IPV6_RULES"
    echo "ip6tables -P OUTPUT ACCEPT" >> "$IPV6_RULES"
    echo "ip6tables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT" >> "$IPV6_RULES"
    echo "ip6tables -A INPUT -i lo -j ACCEPT" >> "$IPV6_RULES"
    echo "ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT" >> "$IPV6_RULES"

    while read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        proto=$(echo "$line" | cut -d: -f1)
        ports=$(echo "$line" | cut -d: -f2- | tr -d ' ')
        case "$proto" in
            tcp)
                for port in $(echo "$ports" | tr ',' ' '); do
                    [[ "$port" == "$SSH_PORT" ]] && continue
                    echo "ip6tables -A INPUT -p tcp --dport $port -j ACCEPT" >> "$IPV6_RULES"
                done
                ;;
            udp)
                for port in $(echo "$ports" | tr ',' ' '); do
                    echo "ip6tables -A INPUT -p udp --dport $port -j ACCEPT" >> "$IPV6_RULES"
                done
                ;;
            icmp)
                echo "ip6tables -A INPUT -p ipv6-icmp -j ACCEPT" >> "$IPV6_RULES"
                ;;
        esac
    done < "$PROT_FILE"

    chmod +x "$IPV6_RULES"
    "$IPV6_RULES"
}

save_persistent_rules() {
    echo "💾 保存规则到持久化存储..."
    netfilter-persistent save
}

create_systemd_timer() {
    SERVICE_FILE="/etc/systemd/system/firewall-auto.service"
    TIMER_FILE="/etc/systemd/system/firewall-auto.timer"

    if [ ! -f "$SERVICE_FILE" ]; then
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=自动应用防火墙规则
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/firewall.sh
EOF
        systemctl daemon-reload
        systemctl enable firewall-auto.service
        echo "✅ 已创建 systemd 服务文件: $SERVICE_FILE"
    fi

    if [ ! -f "$TIMER_FILE" ]; then
        cat > "$TIMER_FILE" <<EOF
[Unit]
Description=每分钟检查并应用防火墙规则

[Timer]
OnUnitActiveSec=60s
Persistent=true

[Install]
WantedBy=timers.target
EOF
        systemctl daemon-reload
        systemctl enable --now firewall-auto.timer
        echo "✅ 已创建 systemd timer 文件: $TIMER_FILE 并启动"
    fi
}

show_firewall_summary() {
    echo "===== 当前防火墙规则汇总 ====="
    echo "IPv4 支持: $([ $IPV4 -eq 1 ] && echo true || echo false) | IPv6 支持: $([ $IPV6 -eq 1 ] && echo true || echo false)"

    # SSH 端口
    echo "1. SSH 端口: $SSH_PORT"

    # TCP 端口
    TCP4=(); TCP6=()
    [ $IPV4 -eq 1 ] && TCP4=($(iptables -S INPUT | grep "\-p tcp" | grep -- '--dport' | awk -F'--dport ' '{print $2}' | awk '{print $1}'))
    [ $IPV6 -eq 1 ] && TCP6=($(ip6tables -S INPUT | grep "\-p tcp" | grep -- '--dport' | awk -F'--dport ' '{print $2}' | awk '{print $1}'))
    TCP_ALL=$(printf "%s\n" "${TCP4[@]}" "${TCP6[@]}" | sort -n | uniq)
    echo "2. TCP 端口: [合并 IPv4+IPv6] $TCP_ALL"

    # UDP 端口
    UDP4=(); UDP6=()
    [ $IPV4 -eq 1 ] && UDP4=($(iptables -S INPUT | grep "\-p udp" | grep -- '--dport' | awk -F'--dport ' '{print $2}' | awk '{print $1}'))
    [ $IPV6 -eq 1 ] && UDP6=($(ip6tables -S INPUT | grep "\-p udp" | grep -- '--dport' | awk -F'--dport ' '{print $2}' | awk '{print $1}'))
    UDP_ALL=$(printf "%s\n" "${UDP4[@]}" "${UDP6[@]}" | sort -n | uniq)
    echo "3. UDP 端口: [合并 IPv4+IPv6] $UDP_ALL"

    # ICMP 状态
    echo "4. ICMP 状态:"
    [ $IPV4 -eq 1 ] && iptables -S INPUT | grep -q "\-p icmp" && echo "  IPv4: 开启" || echo "  IPv4: 关闭"
    [ $IPV6 -eq 1 ] && ip6tables -S INPUT | grep -q "\-p ipv6-icmp" && echo "  IPv6: 开启" || echo "  IPv6: 关闭"

    # 出站状态
    echo "5. 出站状态:"
    [ $IPV4 -eq 1 ] && iptables -S OUTPUT | grep -q "DROP" && echo "  IPv4: 限制" || echo "  IPv4: 允许"
    [ $IPV6 -eq 1 ] && ip6tables -S OUTPUT | grep -q "DROP" && echo "  IPv6: 限制" || echo "  IPv6: 允许"

    echo "=============================="
}

### 主流程 ###
check_root
install_persistent
init_prot_file
detect_stack
get_ssh_port
create_systemd_timer

if prot_modified; then
    [ $IPV4 -eq 1 ] && generate_ipv4_rules
    [ $IPV6 -eq 1 ] && generate_ipv6_rules
    save_persistent_rules
    update_last_mod
    show_firewall_summary
    echo "✅ 防火墙规则已应用并永久保存。SSH端口始终放行。"
else
    echo "ℹ️ prot 文件未修改，防火墙规则保持不变。"
    show_firewall_summary
fi
