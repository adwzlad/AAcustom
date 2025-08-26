#!/bin/bash
# 防火墙交互式配置脚本 (Debian/Ubuntu)
# 功能: 分类放行端口、添加/删除、端口范围支持、快捷端口、动态SSH保护、实时状态显示

# 颜色
GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

# 检查防火墙
check_firewall() {
    if command -v ufw &>/dev/null; then
        FIREWALL="ufw"
    else
        echo -e "${RED}未检测到防火墙，正在安装 UFW...${RESET}"
        apt update && apt install -y ufw
        FIREWALL="ufw"
    fi
}

# 获取已放行端口
get_allowed_ports() {
    local type=$1
    case $type in
        ssh)
            ufw status | grep -E "^[0-9]+.*tcp" | awk '{print $1}' ;;
        tcp)
            ufw status | grep "/tcp" | awk '{print $1}' | sed 's|/tcp||g' | tr '\n' ',' | sed 's/,$//' ;;
        udp)
            ufw status | grep "/udp" | awk '{print $1}' | sed 's|/udp||g' | tr '\n' ',' | sed 's/,$//' ;;
        icmp)
            ufw status verbose | grep -q "ALLOW IN.*ICMP" && echo "已允许" || echo "未允许" ;;
        out)
            ufw status verbose | grep -q "ALLOW OUT" && echo "已允许" || echo "未允许" ;;
    esac
}

# 显示当前防火墙状态
show_current_status() {
    ssh_status=$(get_allowed_ports ssh)
    tcp_status=$(get_allowed_ports tcp)
    udp_status=$(get_allowed_ports udp)
    icmp_status=$(get_allowed_ports icmp)
    out_status=$(get_allowed_ports out)

    echo -e "\n--- 当前防火墙状态 ---"
    echo -e "SSH: ${GREEN}${ssh_status:-无}${RESET}"
    echo -e "TCP: ${GREEN}${tcp_status:-无}${RESET}"
    echo -e "UDP: ${GREEN}${udp_status:-无}${RESET}"
    echo -e "ICMP: ${GREEN}${icmp_status}${RESET}"
    echo -e "出站: ${GREEN}${out_status}${RESET}"
    echo -e "------------------------\n"
}

# SSH端口保护，每步操作前调用
ensure_ssh_port() {
    read -p "请输入当前 SSH 端口（默认 22）: " ssh_port
    ssh_port=${ssh_port:-22}
    if ! ufw status | grep -q "^${ssh_port}.*tcp"; then
        echo -e "${RED}SSH端口 ${ssh_port} 未放行，自动添加以防失联${RESET}"
        ufw allow $ssh_port/tcp
    fi
}

# 添加规则
allow_rule() {
    local rule=$1
    local proto=$2
    if ufw status | grep -q "^${rule}"; then
        echo -e "${GREEN}端口 ${rule}/${proto} 已存在，跳过${RESET}"
    else
        ufw allow $rule/$proto
        echo -e "${GREEN}已放行 ${rule}/${proto}${RESET}"
    fi
}

# 删除规则
delete_rule() {
    local rule=$1
    local proto=$2
    if ufw status | grep -q "^${rule}"; then
        ufw delete allow $rule/$proto
        echo -e "${RED}已删除 ${rule}/${proto}${RESET}"
    else
        echo -e "${RED}端口 ${rule}/${proto} 不存在，无法删除${RESET}"
    fi
}

# 处理端口范围
process_ports() {
    local input=$1
    local action=$2
    local proto=$3
    for p in $input; do
        if [[ $p =~ ^[0-9]+-[0-9]+$ ]]; then
            start=${p%-*}
            end=${p#*-}
            for ((i=start;i<=end;i++)); do
                $action $i $proto
            done
        else
            $action $p $proto
        fi
    done
}

# SSH 菜单
ssh_menu() {
    ensure_ssh_port
    echo -e "\nSSH 端口操作:"
    echo "1) 添加"
    echo "2) 删除"
    read -p "选择 [1-2]: " a
    read -p "请输入 SSH 端口（默认22）: " ssh_port
    ssh_port=${ssh_port:-22}
    case $a in
        1) allow_rule $ssh_port tcp ;;
        2) delete_rule $ssh_port tcp ;;
        *) echo "无效操作" ;;
    esac
    show_current_status
}

# TCP 菜单
tcp_menu() {
    ensure_ssh_port
    current=$(get_allowed_ports tcp)
    echo -e "\n已放行 TCP 端口: ${current:-无}"
    echo "1) 添加"
    echo "2) 删除"
    read -p "选择 [1-2]: " a
    read -p "输入端口（支持单个/空格多个/范围如1000-2000）: " ports
    if [ "$a" = "1" ]; then
        process_ports "$ports" allow_rule tcp
    elif [ "$a" = "2" ]; then
        process_ports "$ports" delete_rule tcp
    else
        echo "无效操作"
    fi
    show_current_status
}

# UDP 菜单
udp_menu() {
    ensure_ssh_port
    current=$(get_allowed_ports udp)
    echo -e "\n已放行 UDP 端口: ${current:-无}"
    echo "1) 添加"
    echo "2) 删除"
    read -p "选择 [1-2]: " a
    read -p "输入端口（支持单个/空格多个/范围如1000-2000）: " ports
    if [ "$a" = "1" ]; then
        process_ports "$ports" allow_rule udp
    elif [ "$a" = "2" ]; then
        process_ports "$ports" delete_rule udp
    else
        echo "无效操作"
    fi
    show_current_status
}

# ICMP 菜单
icmp_menu() {
    ensure_ssh_port
    current=$(get_allowed_ports icmp)
    echo -e "\nICMP 当前状态: $current"
    echo "1) 允许"
    echo "2) 禁止"
    read -p "选择 [1-2]: " a
    if [ "$a" = "1" ]; then
        ufw allow proto icmp
        echo -e "${GREEN}ICMP 已允许${RESET}"
    elif [ "$a" = "2" ]; then
        ufw delete allow proto icmp
        echo -e "${RED}ICMP 已禁止${RESET}"
    else
        echo "无效操作"
    fi
    show_current_status
}

# 出站菜单
out_menu() {
    ensure_ssh_port
    current=$(get_allowed_ports out)
    echo -e "\n出站当前状态: $current"
    echo "1) 允许所有出站"
    echo "2) 禁止所有出站"
    read -p "选择 [1-2]: " a
    if [ "$a" = "1" ]; then
        ufw default allow outgoing
        echo -e "${GREEN}已允许所有出站流量${RESET}"
    elif [ "$a" = "2" ]; then
        ufw default deny outgoing
        echo -e "${RED}已禁止所有出站流量${RESET}"
    else
        echo "无效操作"
    fi
    show_current_status
}

# 快捷常用端口菜单
quick_menu() {
    ensure_ssh_port
    echo -e "\n快捷常用端口操作: HTTP 80, HTTPS 443, DNS 53 + 当前 SSH 端口"
    read -p "请输入当前 SSH 端口（默认 22）: " ssh_port
    ssh_port=${ssh_port:-22}

    echo "1) 添加所有"
    echo "2) 删除所有"
    read -p "选择 [1-2]: " a

    ports_tcp="$ssh_port 80 443"
    ports_udp="53"

    if [ "$a" = "1" ]; then
        process_ports "$ports_tcp" allow_rule tcp
        process_ports "$ports_udp" allow_rule udp
    elif [ "$a" = "2" ]; then
        process_ports "$ports_tcp" delete_rule tcp
        process_ports "$ports_udp" delete_rule udp
    else
        echo "无效操作"
    fi
    show_current_status
}

# 主菜单
main_menu() {
    while true; do
        ssh_status=$(get_allowed_ports ssh)
        tcp_status=$(get_allowed_ports tcp)
        udp_status=$(get_allowed_ports udp)
        icmp_status=$(get_allowed_ports icmp)
        out_status=$(get_allowed
