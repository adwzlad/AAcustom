#!/bin/bash

set -euo pipefail


# ==============================
# 自动安装依赖
# ==============================

install_if_missing() {
    if ! command -v "$1" &>/dev/null; then
        echo "正在安装 $1 ..."
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$2"
    fi
}


# ==============================
# Root 检查
# ==============================

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请使用 root 权限运行此脚本"
        exit 1
    fi
}


# ==============================
# 重启 SSH
# ==============================

restart_ssh() {
    echo "重启 SSH 服务..."
    systemctl restart ssh || systemctl restart sshd
}


# ==============================
# 开启 root 登录
# ==============================

enable_root_login() {

    echo "开启 root 密码登录..."

    grep -q "^PermitRootLogin" /etc/ssh/sshd_config \
    && sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    || echo "PermitRootLogin yes" >> /etc/ssh/sshd_config


    grep -q "^PasswordAuthentication" /etc/ssh/sshd_config \
    && sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    || echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config


    restart_ssh
}


# ==============================
# 修改用户密码
# ==============================

change_user_password() {

    read -p "请输入要修改密码的用户名（默认 root）: " user
    user=${user:-root}


    if id "$user" &>/dev/null; then

        read -p "请输入新密码: " newpass

        echo "$user:$newpass" | chpasswd

        echo "密码修改完成"

    else
        echo "用户不存在"
    fi
}



# ==============================
# 修改 SSH 端口
# ==============================

change_ssh_port() {

    read -p "请输入 SSH 端口（默认 36098）: " port
    port=${port:-36098}


    grep -q "^Port" /etc/ssh/sshd_config \
    && sed -i "s/^Port.*/Port $port/" /etc/ssh/sshd_config \
    || echo "Port $port" >> /etc/ssh/sshd_config


    echo "SSH 端口修改为 $port"

    restart_ssh
}



# ==============================
# 设置语言
# ==============================

change_locale() {

    install_if_missing locale locales


    echo "请选择系统语言:"
    echo "1. 英语 en_US.UTF-8"
    echo "2. 简体中文 zh_CN.UTF-8"
    echo "3. 繁体中文 zh_TW.UTF-8"


    read -p "选择: " lang_choice


    case $lang_choice in

        1)
            lang="en_US.UTF-8"
            ;;

        2)
            lang="zh_CN.UTF-8"
            ;;

        3)
            lang="zh_TW.UTF-8"
            ;;

        *)
            echo "错误"
            return
            ;;
    esac


    sed -i "s/^# *$lang/$lang/" /etc/locale.gen

    echo "LANG=$lang" > /etc/default/locale


    locale-gen

    update-locale LANG=$lang


    echo "完成，请重新登录生效"
}



# ==============================
# 设置时区
# ==============================

set_timezone() {


    echo "请选择时区:"
    echo "1. Asia/Taipei"
    echo "2. Asia/Hong_Kong"
    echo "3. Asia/Singapore"
    echo "4. Australia/Darwin"
    echo "5. 自动检测"


    read -p "选择: " tz_choice


    install_if_missing curl curl


    case $tz_choice in

        1)
            timedatectl set-timezone Asia/Taipei
            ;;

        2)
            timedatectl set-timezone Asia/Hong_Kong
            ;;

        3)
            timedatectl set-timezone Asia/Singapore
            ;;

        4)
            timedatectl set-timezone Australia/Darwin
            ;;

        5)

            timezone=$(curl -s https://ipapi.co/timezone)

            if [ -n "$timezone" ]; then
                timedatectl set-timezone "$timezone"
            fi
            ;;

        *)
            echo "错误"
            ;;
    esac


    timedatectl | grep "Time zone"
}




# ==============================
# Swap 管理
# ==============================

enable_swap() {


    echo ""
    echo "当前 Swap 状态:"
    free -h

    swapon --show || true

    echo ""


    read -p "输入交换内存大小 GB（0关闭）: " swapsize



    # ----------
    # 关闭 swap
    # ----------

    if [[ "$swapsize" == "0" ]]; then


        echo "关闭所有 swap..."


        swap_list=$(swapon --show=NAME --noheadings || true)


        if [ -n "$swap_list" ]; then

            while read -r swapfile; do

                echo "关闭 $swapfile"

                swapoff "$swapfile" || true

            done <<< "$swap_list"

        fi



        echo "清理 fstab..."

        sed -i \
        -e '\|/swapfile|d' \
        -e '\|/swap.img|d' \
        /etc/fstab



        echo "Swap 已永久关闭"

        free -h

        return

    fi



    # ----------
    # 创建 swap
    # ----------


    if [[ "$swapsize" =~ ^[0-9]+$ ]] && [ "$swapsize" -le 64 ]; then


        swapfile="/swapfile"


        echo "创建 ${swapsize}G swap"



        swapoff -a || true



        rm -f /swapfile /swap.img



        sed -i \
        -e '\|/swapfile|d' \
        -e '\|/swap.img|d' \
        /etc/fstab



        dd if=/dev/zero \
        of="$swapfile" \
        bs=1M \
        count=$((swapsize*1024)) \
        status=progress



        chmod 600 "$swapfile"



        mkswap "$swapfile"


        swapon "$swapfile"



        echo "$swapfile none swap sw 0 0" >> /etc/fstab



        echo "Swap 创建完成"

        swapon --show

        free -h


    else

        echo "输入错误"

    fi
}




# ==============================
# 主菜单
# ==============================

main_menu() {


    check_root


    while true
    do

        echo ""
        echo "========== Debian/Ubuntu 管理脚本 =========="
        echo "1. 开启 root 密码登录"
        echo "2. 修改用户密码"
        echo "3. 修改 SSH 端口"
        echo "4. 修改系统语言"
        echo "5. 设置时区"
        echo "6. Swap 管理"
        echo "0. 退出"


        read -p "输入选项（支持组合，例如 123）: " choices



        for choice in $(echo "$choices" | grep -o .)
        do

            case $choice in

                1)
                    enable_root_login
                    ;;

                2)
                    change_user_password
                    ;;

                3)
                    change_ssh_port
                    ;;

                4)
                    change_locale
                    ;;

                5)
                    set_timezone
                    ;;

                6)
                    enable_swap
                    ;;

                0)
                    exit 0
                    ;;

                *)
                    echo "无效选项"
                    ;;

            esac

        done

    done

}



main_menu
