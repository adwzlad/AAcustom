#!/bin/bash

set -e

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
  echo "请以 root 权限运行此脚本！"
  exit 1
fi

# 自动安装依赖包
install_dependencies() {
  apt-get update
  apt-get install -y curl locales tzdata
}

restart_ssh() {
  echo "正在重启 SSH 服务..."
  systemctl restart ssh || systemctl restart sshd
}

# 1. 开启 root 密码登录
enable_root_login() {
  echo "开启 root 密码登录..."
  sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
  sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config
  restart_ssh
  echo "已开启 root 密码登录。"
}

# 2. 修改账户密码
change_user_password() {
  read -p "请输入要修改密码的用户名（默认 root）: " user
  user=${user:-root}

  if ! id "$user" &>/dev/null; then
    echo "用户 $user 不存在！"
    return
  fi

  read -p "请输入新密码（明文输入）: " new_pass
  echo "$user:$new_pass" | chpasswd
  echo "已修改 $user 的密码。"
  restart_ssh
}

# 3. 修改 SSH 端口
change_ssh_port() {
  read -p "请输入新的 SSH 端口（默认 36098）: " new_port
  new_port=${new_port:-36098}

  sed -i "s/^#\?Port .*/Port $new_port/" /etc/ssh/sshd_config
  echo "已修改 SSH 端口为 $new_port。"
  restart_ssh
}

# 4. 修改系统语言
change_language() {
  echo "选择系统语言:"
  echo "1. 英语 (en_US.UTF-8)"
  echo "2. 简体中文 (zh_CN.UTF-8)"
  echo "3. 繁体中文 (zh_TW.UTF-8)"
  read -p "请输入选项 [1-3]: " lang_option

  case $lang_option in
    1) lang="en_US.UTF-8" ;;
    2) lang="zh_CN.UTF-8" ;;
    3) lang="zh_TW.UTF-8" ;;
    *) echo "无效选项。"; return ;;
  esac

  echo "设置语言为 $lang..."
  sed -i "s/^# *$lang/$lang/" /etc/locale.gen || echo "$lang UTF-8" >> /etc/locale.gen
  locale-gen
  update-locale LANG=$lang
  echo "系统语言已设置为 $lang。请重新登录生效。"
}

# 5. 设置系统时区
set_timezone() {
  echo "选择时区:"
  echo "1. 台北 (Asia/Taipei)"
  echo "2. 香港 (Asia/Hong_Kong)"
  echo "3. 新加坡 (Asia/Singapore)"
  echo "4. 自动设置（基于公网 IP）"
  read -p "请输入选项 [1-4]: " tz_option

  case $tz_option in
    1) tz="Asia/Taipei" ;;
    2) tz="Asia/Hong_Kong" ;;
    3) tz="Asia/Singapore" ;;
    4)
      echo "正在自动检测时区..."
      tz=$(curl -s --max-time 10 http://worldtimeapi.org/api/ip | grep '"timezone"' | cut -d\" -f4)
      if [[ -z "$tz" ]]; then
        echo "无法自动获取时区。"
        return
      fi
      ;;
    *) echo "无效选项。"; return ;;
  esac

  timedatectl set-timezone "$tz"
  echo "时区已设置为 $tz。"
}

main_menu() {
  echo "=== Debian 系统设置脚本 ==="
  echo "1. 开启 root 密码登录"
  echo "2. 修改账户密码"
  echo "3. 修改 SSH 端口"
  echo "4. 修改系统语言"
  echo "5. 设置系统时区"
  echo "0. 退出"
  echo "=========================="

  read -p "请输入选项 [0-5]: " choice

  case $choice in
    1) enable_root_login ;;
    2) change_user_password ;;
    3) change_ssh_port ;;
    4) change_language ;;
    5) set_timezone ;;
    0) exit 0 ;;
    *) echo "无效选项。" ;;
  esac
}

install_dependencies

while true; do
  main_menu
  echo
done
