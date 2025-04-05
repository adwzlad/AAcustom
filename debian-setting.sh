#!/bin/bash

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
   echo "请以 root 用户运行此脚本。"
   exit 1
fi

# 定义颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# 修改用户密码
change_password() {
    read -p "请输入要修改密码的用户名 (默认 root): " username
    username=${username:-root}
    if id "$username" &>/dev/null; then
        read -s -p "请输入新密码: " password
        echo
        echo "$username:$password" | chpasswd
        echo -e "${GREEN}密码修改成功。${RESET}"
    else
        echo -e "${RED}用户 $username 不存在。${RESET}"
    fi
}

# 开启 root SSH 登录
enable_root_ssh_login() {
    sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
    echo -e "${GREEN}已启用 root 用户 SSH 登录。${RESET}"
}

# 开启 root 密码登录
enable_password_auth() {
    sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config
    echo -e "${GREEN}已启用 SSH 密码验证。${RESET}"
}

# 修改 SSH 端口
change_ssh_port() {
    read -p "请输入新的 SSH 端口 (1-65535): " new_port
    if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
        sed -i "s/^#\?Port .*/Port $new_port/" /etc/ssh/sshd_config
        echo -e "${GREEN}SSH 端口已修改为 $new_port。${RESET}"
    else
        echo -e "${RED}无效的端口号。${RESET}"
    fi
}

# 配置语言
set_locale() {
    echo "选择系统语言："
    echo "1) 简体中文"
    echo "2) 繁体中文"
    echo "3) 英语"
    read -p "请输入选项 (1-3): " locale_choice

    case $locale_choice in
        1) locale="zh_CN.UTF-8" ;;
        2) locale="zh_TW.UTF-8" ;;
        3) locale="en_US.UTF-8" ;;
        *) echo -e "${RED}无效选项。${RESET}"; return ;;
    esac

    apt-get update -qq
    apt-get install -y locales
    sed -i "s/^# $locale/$locale/" /etc/locale.gen
    echo "LANG=$locale" > /etc/default/locale
    locale-gen
    echo -e "${GREEN}语言设置为 $locale。${RESET}"
}

# 设置时区
set_timezone() {
    echo "选择时区："
    echo "1) 香港 (Asia/Hong_Kong)"
    echo "2) 台湾 (Asia/Taipei)"
    echo "3) 新加坡 (Asia/Singapore)"
    echo "4) 日本 (Asia/Tokyo)"
    echo "5) 自动根据 IP 设置"
    read -p "请输入选项 (1-5): " tz_choice

    case $tz_choice in
        1) timezone="Asia/Hong_Kong" ;;
        2) timezone="Asia/Taipei" ;;
        3) timezone="Asia/Singapore" ;;
        4) timezone="Asia/Tokyo" ;;
        5)
            apt-get install -y curl
            timezone=$(curl -s http://worldtimeapi.org/api/ip | grep -oP '(?<="timezone":")[^"]+')
            ;;
        *) echo -e "${RED}无效选项。${RESET}"; return ;;
    esac

    if [ -n "$timezone" ]; then
        timedatectl set-timezone "$timezone"
        echo -e "${GREEN}时区设置为 $timezone。${RESET}"
    else
        echo -e "${RED}无法获取时区信息。${RESET}"
    fi
}

# 主菜单循环
while true; do
    echo
    echo -e "${YELLOW}===== 系统配置脚本 =====${RESET}"
    echo "1) 修改用户密码"
    echo "2) 开启 SSH root 登录"
    echo "3) 开启 SSH 密码登录"
    echo "4) 修改 SSH 端口"
    echo "5) 配置系统语言"
    echo "6) 设置系统时区"
    echo "0) 退出脚本"
    read -p "请选择操作 (0-6): " choice

    case $choice in
        1) change_password ;;
        2) enable_root_ssh_login ;;
        3) enable_password_auth ;;
        4) change_ssh_port ;;
        5) set_locale ;;
        6) set_timezone ;;
        0)
            echo -e "${YELLOW}正在退出，应用更改...${RESET}"
            systemctl restart ssh
            echo -e "${GREEN}所有更改已应用并 SSH 重启完成。${RESET}"
            exit 0
            ;;
        *) echo -e "${RED}无效的输入，请重新选择。${RESET}" ;;
    esac
done
