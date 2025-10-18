#!/bin/bash

set -e

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 自动安装依赖
install_if_missing() {
    if ! command -v "$1" &>/dev/null; then
        echo "正在安装 $1 ..."
        dnf install -y "$2"
    fi
}

restart_ssh() {
    echo "重启 SSH 服务..."
    systemctl restart sshd
}

# 1. 启用 root 密码登录
enable_root_login() {
    echo "开启 root 密码登录..."
    sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
    sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config
    restart_ssh
}

# 2. 修改账户密码
change_user_password() {
    read -p "请输入要修改密码的用户名（默认 root）: " user
    user=${user:-root}
    if id "$user" &>/dev/null; then
        read -p "请输入新密码（明文）: " newpass
        echo "$user:$newpass" | chpasswd
        echo "密码已修改。"
        restart_ssh
    else
        echo "用户 $user 不存在。"
    fi
}

# 3. 修改 SSH 端口（含 SELinux）
change_ssh_port() {
    read -p "请输入要修改的 SSH 端口（默认 36098）: " port
    port=${port:-36098}
    sed -i "s/^#\?Port .*/Port $port/" /etc/ssh/sshd_config

    # 若启用 SELinux，需更新防火墙规则
    if command -v semanage &>/dev/null; then
        semanage port -a -t ssh_port_t -p tcp "$port" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "$port" || true
    fi

    if systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --permanent --add-port=${port}/tcp || true
        firewall-cmd --reload || true
    fi

    echo "SSH 端口已修改为 $port"
    restart_ssh
}

# 4. 修改系统语言
change_locale() {
    echo "请选择系统语言:"
    echo "1. 英语（en_US.UTF-8）"
    echo "2. 简体中文（zh_CN.UTF-8）"
    echo "3. 繁体中文（zh_TW.UTF-8）"
    read -p "选择语言 (1-3): " lang_choice
    install_if_missing localedef glibc-langpack-en

    case $lang_choice in
        1) lang="en_US.UTF-8" ;;
        2) lang="zh_CN.UTF-8" ;;
        3) lang="zh_TW.UTF-8" ;;
        *) echo "无效选择。"; return ;;
    esac

    echo "设置语言为 $lang"
    localedef -c -i "${lang%%.*}" -f UTF-8 "$lang" 2>/dev/null || true
    echo "LANG=$lang" > /etc/locale.conf
    export LANG=$lang
    echo "语言设置完成。请重新登录以生效。"
}

# 5. 设置系统时区
set_timezone() {
    echo "请选择时区："
    echo "1. 台北（Asia/Taipei）"
    echo "2. 香港（Asia/Hong_Kong）"
    echo "3. 新加坡（Asia/Singapore）"
    echo "4. 自动设置（基于公网 IP）"
    read -p "选择时区 (1-4): " tz_choice

    install_if_missing curl curl

    case $tz_choice in
        1) timedatectl set-timezone Asia/Taipei ;;
        2) timedatectl set-timezone Asia/Hong_Kong ;;
        3) timedatectl set-timezone Asia/Singapore ;;
        4)
            timezone=$(curl -s https://ipapi.co/timezone)
            if [ -n "$timezone" ]; then
                timedatectl set-timezone "$timezone"
                echo "已自动设置时区为 $timezone"
            else
                echo "无法自动检测时区。"
            fi
            ;;
        *) echo "无效选择。" ;;
    esac
}

# 6. 设置交换内存（swap）
enable_swap() {
    read -p "请输入要设置的交换内存大小（单位 GB，例如 2）: " swapsize
    if [[ "$swapsize" =~ ^[0-9]+$ ]]; then
        swapsize_mb=$((swapsize * 1024))
        swapfile="/swapfile"
        echo "创建 ${swapsize}G 交换内存..."
        fallocate -l "${swapsize_mb}M" "$swapfile" || dd if=/dev/zero of="$swapfile" bs=1M count="$swapsize_mb"
        chmod 600 "$swapfile"
        mkswap "$swapfile"
        swapon "$swapfile"
        grep -q "$swapfile" /etc/fstab || echo "$swapfile none swap sw 0 0" >> /etc/fstab
        echo "已设置并启用交换内存。"
    else
        echo "无效的数字输入。"
    fi
}

# 主菜单
main_menu() {
    check_root
    while true; do
        echo ""
        echo "==== CentOS 10 管理脚本 ===="
        echo "1. 启用 root 密码登录"
        echo "2. 修改账户密码"
        echo "3. 修改 SSH 端口"
        echo "4. 修改系统语言"
        echo "5. 设置系统时区"
        echo "6. 设置交换内存"
        echo "0. 退出"
        read -p "请输入选项（可多项组合，如 123）: " choices
        for choice in $(echo "$choices" | grep -o .); do
            case $choice in
                1) enable_root_login ;;
                2) change_user_password ;;
                3) change_ssh_port ;;
                4) change_locale ;;
                5) set_timezone ;;
                6) enable_swap ;;
                0) echo "退出。"; exit 0 ;;
                *) echo "无效选项：$choice" ;;
            esac
        done
    done
}

main_menu
